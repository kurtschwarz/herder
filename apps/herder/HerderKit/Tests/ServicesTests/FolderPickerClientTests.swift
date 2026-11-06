import Core
import Foundation
import Services
import TestSupport
import Testing

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct StubFolderPickerClientTests {
    let client = StubFolderPickerClient()

    @Test func cancelsWhenNothingIsScripted() async {
        #expect(await client.pickFolder(startingAt: nil) == nil)
    }

    @Test func answersInTheOrderScripted() async {
        let first = URL(filePath: "/tmp/one")
        let second = URL(filePath: "/tmp/two")
        client.script(first)
        client.script(nil)
        client.script(second)

        #expect(await client.pickFolder(startingAt: nil) == first)
        #expect(await client.pickFolder(startingAt: nil) == nil)
        #expect(await client.pickFolder(startingAt: nil) == second)
        #expect(await client.pickFolder(startingAt: nil) == nil)
    }

    @Test func remembersWhereEachRequestStarted() async {
        let start = URL(filePath: "/tmp/start")
        _ = await client.pickFolder(startingAt: start)
        _ = await client.pickFolder(startingAt: nil)
        #expect(client.starts == [start, nil])
    }

    @Test func countsEveryRequest() async {
        _ = await client.pickFolder(startingAt: nil)
        _ = await client.pickFolder(startingAt: nil)
        #expect(client.requests == 2)
    }
}
