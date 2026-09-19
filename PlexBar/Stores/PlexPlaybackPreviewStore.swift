import Foundation
import Observation
import OSLog

/// Owns one timeline's requests and bounded cache. Pointer movement replaces the
/// pending target rather than starting parallel downloads or starving a slow one.
@MainActor
@Observable
final class PlexPlaybackPreviewStore {
    private(set) var position: TimeInterval?
    private(set) var image: PlexCGImageBox?
    private(set) var message: String?
    private(set) var isLoading = false

    typealias Loader = @Sendable (PlexPlaybackPreviewFrame, PlexServerPlaybackPreviewSource) async throws -> PlexCGImageBox
    @ObservationIgnored private let load: Loader
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let cache = PlexImageMemoryCache(imageCountLimit: 64, imageCostLimit: 16 * 1_024 * 1_024)
    @ObservationIgnored private var source: PlexPlaybackPreviewSource?
    @ObservationIgnored private var target: PlexPlaybackPreviewFrame?
    @ObservationIgnored private var missingParts: Set<Int> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sourceGeneration = 0

    init(interval: Duration = .milliseconds(125), load: @escaping Loader = { frame, source in
        try await PlexPlaybackPreviewClient().image(for: frame, source: source)
    }) {
        self.interval = interval
        self.load = load
    }

    func configure(_ newSource: PlexPlaybackPreviewSource) {
        guard newSource != source else { return }
        hide()
        // Cache instances are scoped by a monotonically changing source generation;
        // credentials never appear in cache keys or diagnostics.
        source = newSource
        sourceGeneration += 1
        missingParts.removeAll()
    }

    func show(at seconds: TimeInterval, source newSource: PlexPlaybackPreviewSource) {
        configure(newSource)
        position = seconds
        guard case .server(let source) = newSource else {
            if case .unavailable(let reason) = newSource { message = reason }
            return
        }
        let frame: PlexPlaybackPreviewFrame
        do { frame = try source.frame(at: seconds) }
        catch {
            target = nil
            image = nil
            isLoading = false
            message = error.localizedDescription
            return
        }
        guard frame != target else { return }
        target = frame
        image = nil
        message = nil
        if missingParts.contains(frame.partID) {
            message = PlexPlaybackPreviewError.noIndex.localizedDescription
            isLoading = false
            return
        }
        if let cached = cache.cgImage(for: cacheKey(frame)) {
            image = PlexCGImageBox(cached)
            isLoading = false
            return
        }
        isLoading = true
        startIfNeeded(source: source)
    }

    func hide() {
        task?.cancel()
        task = nil
        generation += 1
        position = nil
        target = nil
        image = nil
        message = nil
        isLoading = false
    }

    private func cacheKey(_ frame: PlexPlaybackPreviewFrame) -> String {
        "\(sourceGeneration)|\(frame.cacheKey)"
    }

    private func startIfNeeded(source: PlexServerPlaybackPreviewSource) {
        guard task == nil else { return }
        let ticket = generation
        task = Task { [weak self] in
            // Avoid loading a thumbnail for a pointer merely crossing the track.
            do { try await Task.sleep(for: self?.interval ?? .zero) } catch { return }
            while let self, self.generation == ticket, let frame = self.target {
                if self.cache.cgImage(for: self.cacheKey(frame)) != nil || self.missingParts.contains(frame.partID) {
                    break
                }
                let clock = ContinuousClock()
                let started = clock.now
                do {
                    let result = try await self.load(frame, source)
                    guard !Task.isCancelled, self.generation == ticket else { return }
                    self.cache.insert(result.image, for: self.cacheKey(frame))
                    if self.target == frame {
                        self.image = result
                        self.isLoading = false
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == ticket else { return }
                    if error as? PlexPlaybackPreviewError == .noIndex {
                        self.missingParts.insert(frame.partID)
                    }
                    if self.target == frame || self.target?.partID == frame.partID && self.missingParts.contains(frame.partID) {
                        self.message = error.localizedDescription
                        self.isLoading = false
                    }
                    Logger(subsystem: AppConstants.bundleIdentifier, category: "PlaybackPreview")
                        .error("Preview failed for part \(frame.partID): \(error.localizedDescription, privacy: .public)")
                }
                if self.target == frame { break }
                do { try await clock.sleep(until: started.advanced(by: self.interval)) } catch { return }
            }
            guard let self, self.generation == ticket else { return }
            self.task = nil
        }
    }
}
