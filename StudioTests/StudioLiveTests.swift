import Foundation
import ImageIO
import Testing
@testable import PlexBarStudio

/// Explicitly opt in: this test uses the signed-in Codex account's included usage.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLEXBAR_STUDIO_LIVE_TEST"] == "1"))
struct StudioLiveTests {
    @Test @MainActor func generateCatalogAndClayArtworkThroughAppServer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "plexbar-studio-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        let engine = StudioCodexEngine()
        let metadata = try await engine.run(executable: StudioCodexConnection.defaultExecutable, directory: root,
            prompt: StudioTitleDraft.researchPrompt(title: "The General (1926)", kind: "movie", notes: "Verify the original Buster Keaton film. One movie record only."),
            schema: StudioTitleDraft.outputSchema) { thread, model in
                try Data("\(thread)\n\(model)".utf8).write(to: root.appending(path: "catalog-thread.txt"))
            }
        try Data(metadata.text.utf8).write(to: root.appending(path: "catalog-result.json"))
        let draft = try JSONDecoder().decode(StudioTitleDraft.self, from: Data(metadata.text.utf8))
        let compiled = try draft.compile(into: pack)
        #expect(compiled.pack.validate().isEmpty)
        let reference = try #require(pack.assets.first { $0.role == .avatar })
        let referenceURL = root.appending(path: "clay-reference.png")
        try StudioFiles.normalizedReference(at: StudioFiles.resolved(reference.resource, in: StudioFiles.repositoryContentURL)).write(to: referenceURL)
        let result = try await engine.run(executable: StudioCodexConnection.defaultExecutable, directory: root,
            prompt: "Generate exactly one square 1024x1024 image using built-in image generation: a friendly fictional clay train conductor, head and shoulders, tactile matte plasticine, simple muted orange background, no text. Use the attached image only as a clay material reference. Save the generated image in this job directory. Do not use any API key or separate API.",
            references: [referenceURL], requiresImages: true) { thread, model in
                try Data("\(thread)\n\(model)".utf8).write(to: root.appending(path: "artwork-thread.txt"))
            }
        try Data(engine.transcript.utf8).write(to: root.appending(path: "artwork-transcript.txt"))
        try StudioJSON.array(result.images).encoded().write(to: root.appending(path: "artwork-items.json"))
        let image = try #require(result.images.last)
        #expect(image["status"]?.string == "completed")
        let path = try #require(image["savedPath"]?.string)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let exported = try StudioFiles.exportImage(data, role: .avatar)
        try exported.write(to: root.appending(path: "conductor-avatar.png"))
        print("STUDIO_LIVE_OUTPUT=\(root.path)")
    }
}
