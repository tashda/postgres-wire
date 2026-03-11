import Foundation
import PostgresNIO
import NIO
import NIOCore

public struct IPAddress: Equatable, Hashable, Codable {
    public let string: String

    public init(string: String) {
        self.string = string
    }
}

extension IPAddress: PostgresEncodable {
    public var pgDataType: PostgresDataType { .inet }

    public func encode(into: inout PGData) throws {
        into = PGData(string: self.string)
    }
}
