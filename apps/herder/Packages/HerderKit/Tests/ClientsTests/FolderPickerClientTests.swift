import Clients
import ClientsTestSupport
import Foundation
import Testing

/// The fake has to behave like the real thing, or tests written against it lie.
@Suite struct StubFolderPickerClientTests {
    let client = StubFolderPickerClient()

    @Test func cancelsWhenNothingIsScripted() async {
        #expect(await client.pickFolder() == nil)
    }

    @Test func answersInTheOrderScripted() async {
        let first = URL(filePath: "/tmp/one")
        let second = URL(filePath: "/tmp/two")
        client.script(first)
        client.script(nil)
        client.script(second)

        #expect(await client.pickFolder() == first)
        #expect(await client.pickFolder() == nil)
        #expect(await client.pickFolder() == second)
        #expect(await client.pickFolder() == nil)
    }

    @Test func countsEveryRequest() async {
        _ = await client.pickFolder()
        _ = await client.pickFolder()
        #expect(client.requests == 2)
    }
}
