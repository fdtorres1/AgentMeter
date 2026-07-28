import Foundation

public enum StatusJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ snapshot: StatusSnapshot) throws -> Data {
        try makeEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> StatusSnapshot {
        try makeDecoder().decode(StatusSnapshot.self, from: data)
    }

    public static func encodeString(_ snapshot: StatusSnapshot) throws -> String {
        let data = try encode(snapshot)
        guard let string = String(data: data, encoding: .utf8) else {
            throw StatusJSONError.invalidUTF8
        }
        return string
    }
}

public enum StatusJSONError: Error {
    case invalidUTF8
}
