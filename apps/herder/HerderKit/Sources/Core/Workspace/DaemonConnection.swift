import Foundation
import Observation

/// The app's standing with herderd, observed by Settings.
///
/// App-wide, because there is one daemon however many windows are open.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class DaemonConnection {
    public private(set) var status: DaemonStatus = .connecting

    @ObservationIgnored
    private let client: any DaemonClient

    @ObservationIgnored
    private var attempt: Task<Void, Never>?

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Connects once however many times it is asked, while an attempt is
    /// still running. After one has finished, asks again: this is also retry.
    public func connect() async {
        if let attempt {
            await attempt.value
            return
        }
        status = .connecting
        let task = Task { [client] in
            let result = await client.connect()
            self.status = result
            self.attempt = nil
        }
        attempt = task
        await task.value
    }
}
