import Foundation

/// The bytes of herderd's protocol, with no I/O: what a frame looks like, the
/// first message and how to read the answer. The packages/herderd crate is the
/// other half, and `protocol.rs` there says what the messages mean.
public enum DaemonWire {
    /// The versions this build of the app speaks. Raise `supported.upperBound`
    /// when the app starts using a message the daemon gained in that version.
    public static let supported = 1...1

    /// A frame is a big-endian `UInt32` length and then that many bytes.
    public static let headerSize = 4

    /// The most a frame may carry. The daemon refuses more.
    public static let maxFrame = 16 * 1024 * 1024

    public static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        return Data(bytes: &length, count: headerSize) + payload
    }

    /// The payload length a frame header announces, or `nil` if it is not a
    /// header or announces more than a frame may carry.
    public static func payloadLength(header: Data) -> Int? {
        guard header.count == headerSize else { return nil }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        return length <= maxFrame ? length : nil
    }

    /// The first frame on every connection.
    public static func hello(client: String) -> Data {
        let message: [String: Any] = [
            "type": "hello",
            "min_protocol": supported.lowerBound,
            "max_protocol": supported.upperBound,
            "client": client,
        ]
        // Sorted, so what goes out is the same bytes every time.
        let payload = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        return frame(payload ?? Data())
    }

    /// What the daemon's answer to ``hello(client:)`` means for the app.
    public static func status(fromReply payload: Data) -> DaemonStatus {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = object["type"] as? String,
              let version = object["daemon_version"] as? String
        else { return .unavailable(reason: "Unrecognised reply from herderd.") }

        switch type {
        case "welcome":
            guard let negotiated = object["protocol"] as? Int, let host = object["host"] as? String else { break }
            guard supported.contains(negotiated) else {
                return .unavailable(reason: "herderd chose protocol \(negotiated), which this app does not speak.")
            }
            return .connected(DaemonInfo(daemonVersion: version, protocolVersion: negotiated, host: host))
        case "incompatible":
            guard let low = object["min_protocol"] as? Int, let high = object["max_protocol"] as? Int, low <= high
            else { break }
            return .incompatible(daemonVersion: version, supports: low...high, app: supported)
        default:
            break
        }
        return .unavailable(reason: "Unrecognised reply from herderd.")
    }
}
