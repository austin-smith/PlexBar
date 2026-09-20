import Foundation

/// Retains all PMS fields without teaching the editor every version of the Plex contract.
enum StudioJSON: Codable, Equatable, Sendable {
    case object([String: StudioJSON])
    case array([StudioJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: StudioJSON].self) { self = .object(value) }
        else { self = .array(try container.decode([StudioJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(_ key: String) -> StudioJSON? {
        get { object?[key] }
        set {
            guard case .object(var values) = self else { return }
            values[key] = newValue
            self = .object(values)
        }
    }

    var object: [String: StudioJSON]? { if case .object(let value) = self { value } else { nil } }
    var array: [StudioJSON]? { if case .array(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var integer: Int? {
        guard let number, number.isFinite, number.rounded() == number,
              number >= Double(Int.min), number < Double(Int.max) else { return nil }
        return Int(number)
    }

    static func strings(_ values: [String]) -> StudioJSON { .array(values.map(Self.string)) }
    static func integer(_ value: Int) -> StudioJSON { .number(Double(value)) }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    var prettyPrinted: String { (try? encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}
