import PlexModels
import Foundation

public struct PlexPlaybackInfoPresentation: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
        public let value: String

        public init(id: String, label: String, value: String) {
            self.id = id
            self.label = label
            self.value = value
        }

        public init(_ fact: PlexNativeMediaDiagnosticFact) {
            id = fact.kind.rawValue
            label = fact.label
            value = fact.value
        }
    }

    public let item: PlexPlayerPlaybackInfoPresentation
    public let playbackRows: [Row]
    public let videoRows: [Row]
    public let audioRows: [Row]
    public let performanceRows: [Row]

    public init(
        item: PlexMediaItem,
        deliveryLabel: String,
        connectionLabel: String? = nil,
        videoQualityLabel: String?,
        playbackVersionLabel: String? = nil,
        queuePositionLabel: String? = nil,
        waitingReasonLabel: String? = nil,
        audioOutputLabel: String? = nil,
        deliveredMediaFacts: PlexNativeMediaFacts?,
        playbackMetricFacts: [PlexPlaybackMetricDiagnosticFact] = []
    ) {
        self.item = PlexPlayerPlaybackInfoPresentation(item: item)
        var playbackRows = [
            Row(id: "delivery", label: "Delivery", value: deliveryLabel),
        ]
        if let connectionLabel {
            playbackRows.append(Row(
                id: "connection",
                label: "Connection",
                value: connectionLabel
            ))
        }
        if let videoQualityLabel {
            playbackRows.append(Row(
                id: "quality",
                label: "Quality",
                value: videoQualityLabel
            ))
        }
        if let playbackVersionLabel {
            playbackRows.append(Row(
                id: "version",
                label: "Version",
                value: playbackVersionLabel
            ))
        }
        if let queuePositionLabel {
            playbackRows.append(Row(
                id: "queue",
                label: "Queue",
                value: queuePositionLabel
            ))
        }
        if let waitingReasonLabel {
            playbackRows.append(Row(
                id: "waiting",
                label: "Waiting",
                value: waitingReasonLabel
            ))
        }
        self.playbackRows = playbackRows
        videoRows = deliveredMediaFacts?.videoDiagnosticFacts.map(Row.init) ?? []
        var audioRows = deliveredMediaFacts?.audioDiagnosticFacts.map(Row.init) ?? []
        if let audioOutputLabel {
            audioRows.append(Row(
                id: "output",
                label: "Output",
                value: audioOutputLabel
            ))
        }
        self.audioRows = audioRows
        performanceRows = playbackMetricFacts.map { fact in
            Row(
                id: "metric.\(fact.kind.rawValue)",
                label: fact.label,
                value: fact.value
            )
        }
    }
}
