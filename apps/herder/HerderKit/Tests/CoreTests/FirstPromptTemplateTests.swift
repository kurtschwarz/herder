import Foundation
import TestSupport
import Testing

@testable import Core

@Suite struct FirstPromptTemplateTests {
    @Test func theTypedTextGoesWhereThePlaceholderIs() {
        #expect(FirstPromptTemplate.apply("/grill-me {prompt}", to: "add a minimap") == "/grill-me add a minimap")
        #expect(FirstPromptTemplate.apply("{prompt}\n\nBe brief.", to: "add a minimap") == "add a minimap\n\nBe brief.")
    }

    @Test func aTemplateWithNoPlaceholderComesFirst() {
        #expect(FirstPromptTemplate.apply("Use the grill-me skill.", to: "add a minimap")
            == "Use the grill-me skill.\n\nadd a minimap")
    }

    @Test func aBlankTemplateLeavesTheTextAlone() {
        #expect(FirstPromptTemplate.apply("", to: "add a minimap") == "add a minimap")
        #expect(FirstPromptTemplate.apply(" \n", to: "add a minimap") == "add a minimap")
    }

    @Test func everyPlaceholderIsFilled() {
        #expect(FirstPromptTemplate.apply("{prompt} / {prompt}", to: "x") == "x / x")
    }
}

@Suite @MainActor struct FirstPromptTemplateSettingTests {
    let state = InMemoryStateStore()

    @Test func itIsJustThePromptUntilSet() {
        #expect(AgentCatalog(state: state).firstPromptTemplate == "")
    }

    @Test func itSurvivesARelaunch() async {
        let catalog = AgentCatalog(state: state)
        catalog.setFirstPromptTemplate("/grill-me {prompt}")
        await catalog.flushSaves()

        let relaunched = AgentCatalog(state: state)
        await relaunched.load()

        #expect(relaunched.firstPromptTemplate == "/grill-me {prompt}")
    }

    @Test func aSnapshotFromBeforeItExistedStillReads() throws {
        let decoded = try JSONDecoder().decode(AgentsSnapshot.self, from: Data(#"{"version":1,"custom":[]}"#.utf8))
        #expect(decoded.firstPromptTemplate == nil)
    }
}
