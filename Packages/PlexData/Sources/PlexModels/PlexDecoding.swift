import Foundation

extension KeyedDecodingContainer {
    public func decodePlexString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected a Plex string or integer value."
            )
        )
    }

    public func decodePlexStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    public func decodePlexIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    public func decodePlexInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    public func decodePlexDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    public func decodePlexBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = decodePlexIntIfPresent(forKey: key) {
            return value != 0
        }
        return nil
    }
}
