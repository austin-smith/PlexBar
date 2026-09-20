import Foundation

struct StudioValidationIssue: Identifiable, Equatable, Sendable {
    var context: String
    var message: String
    var id: String { context + ":" + message }
}
