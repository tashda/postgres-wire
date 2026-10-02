import Foundation
import PostgresNIO
import NIO
import NIOCore

public struct MACAddress: Equatable, Hashable, Codable {
    public let string: String

    public init(string: String) {
        self.string = string
    }
}

extension MACAddress: PostgresEncodable {
    public var pgDataType: PostgresDataType { .macaddr }

    public func encode(into: inout PGData) throws {
        // MAC addresses are typically 6 bytes.
        // We need to parse the string into a byte buffer.
        // For simplicity, assuming the string is always in the format "XX:XX:XX:XX:XX:XX"
        let components = self.string.split(separator: ":").map { String($0) }
        guard components.count == 6 else {
            throw PostgresError.encodingError(
                message: "Invalid MAC address format: \(self.string)",
                type: MACAddress.self
            )
        }

        var buffer = ByteBufferAllocator().buffer(capacity: 6)
        for component in components {
            guard let byte = UInt8(component, radix: 16) else {
                throw PostgresError.encodingError(
                    message: "Invalid MAC address component: \(component) in \(self.string)",
                    type: MACAddress.self
                )
            }
            buffer.writeInteger(byte)
        }
        into = PGData(type: .macaddr, value: buffer)
    }
}