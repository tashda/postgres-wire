import PostgresNIO
import Foundation

public protocol PostgresEncodable {
    var pgDataType: PostgresDataType { get }
    func encode(into: inout PGData) throws
}

public protocol JSONBEncodable: Encodable, PostgresEncodable {}

extension String: PostgresEncodable {
    public var pgDataType: PostgresDataType { .text }
    public func encode(into: inout PGData) throws {
        into = PGData(string: self)
    }
}

extension Int: PostgresEncodable {
    public var pgDataType: PostgresDataType { .int8 }
    public func encode(into: inout PGData) throws {
        into = PGData(int: self)
    }
}

extension Double: PostgresEncodable {
    public var pgDataType: PostgresDataType { .float8 }
    public func encode(into: inout PGData) throws {
        into = PGData(double: self)
    }
}

extension Bool: PostgresEncodable {
    public var pgDataType: PostgresDataType { .bool }
    public func encode(into: inout PGData) throws {
        into = PGData(bool: self)
    }
}

extension UUID: PostgresEncodable {
    public var pgDataType: PostgresDataType { .uuid }
    public func encode(into: inout PGData) throws {
        into = PGData(uuid: self)
    }
}

extension Date: PostgresEncodable {
    public var pgDataType: PostgresDataType { .date }
    public func encode(into: inout PGData) throws {
        into = PGData(date: self)
    }
}

extension Data: PostgresEncodable {
    public var pgDataType: PostgresDataType { .bytea }
    public func encode(into: inout PGData) throws {
        into = PGData(bytes: self)
    }
}

extension Array: PostgresEncodable where Element: Encodable {
    public var pgDataType: PostgresDataType { .text }
    public func encode(into: inout PGData) throws {
        // For basic types, create PostgreSQL array syntax
        if Element.self == String.self {
            let stringArray = self as! [String]
            let escapedStrings = stringArray.map { string in
                let escaped = string.replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            let arrayString = "{" + escapedStrings.joined(separator: ",") + "}"
            into = PGData(string: arrayString)
        } else if Element.self == Int.self {
            let intArray = self as! [Int]
            let arrayString = "{" + intArray.map { String($0) }.joined(separator: ",") + "}"
            into = PGData(string: arrayString)
        } else if Element.self == UUID.self {
            // For UUID arrays, encode as JSON and handle at database level
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            into = PGData(jsonb: data)
        } else {
            // Fallback to JSON encoding for other types
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            into = PGData(jsonb: data)
        }
    }
}

extension JSONBEncodable {
    public var pgDataType: PostgresDataType { .jsonb }
    public func encode(into: inout PGData) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        into = PGData(jsonb: data)
    }
}