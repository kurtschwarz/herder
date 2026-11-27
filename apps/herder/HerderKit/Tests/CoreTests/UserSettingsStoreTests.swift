import Foundation
import TestSupport
import Testing

@testable import Core

@Suite @MainActor struct UserSettingsStoreTests {
    let file = InMemorySettingsFileClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let store: UserSettingsStore

    init() {
        store = UserSettingsStore(file: file, clock: clock)
    }

    func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    static let aider = Agent(id: "aider", name: "Aider", command: "aider", environment: ["EDITOR": "vi"])

    // MARK: - Reading

    @Test func noFileIsEveryDefaultAndWritesNothing() async {
        await store.load()

        #expect(store.settings == UserSettings())
        #expect(store.problem == nil)
        #expect(file.writes.isEmpty)
    }

    @Test func aMissingKeyIsItsDefaultAndAnUnknownOneIsIgnored() async {
        file.edit(#"{"agents":{"first_prompt_template":"/grill-me {prompt}"},"theme":"dark"}"#)

        await store.load()

        var expected = UserSettings()
        expected.firstPromptTemplate = "/grill-me {prompt}"
        #expect(store.settings == expected)
        #expect(store.problem == nil)
    }

    @Test func aFileWithAProblemKeepsTheLastGoodSettingsAndSaysWhat() async {
        file.edit(#"{"updates":{"check_automatically":false}}"#)
        await store.load()
        store.startWatching()

        file.edit(#"{"updates":{"check_automatically":"no"}}"#)
        await settle()

        #expect(store.settings.checkForUpdatesAutomatically == false)
        #expect(store.problem == "updates.check_automatically should be true or false.")

        file.edit(#"{"updates": {"#)
        await settle()
        #expect(store.problem?.hasPrefix("It isn\u{2019}t valid JSON") == true)

        file.edit(#"{"updates":{"check_automatically":true}}"#)
        await settle()
        #expect(store.settings.checkForUpdatesAutomatically)
        #expect(store.problem == nil)
    }

    @Test func aDuplicateOrPresetAgentIDIsAProblem() async {
        file.edit(#"{"agents":{"custom":[{"id":"aider"},{"id":"aider"}]}}"#)
        await store.load()
        #expect(store.problem == "agents.custom[1].id \u{201C}aider\u{201D} is used by another agent.")

        file.edit(#"{"agents":{"custom":[{"id":"codex"}]}}"#)
        await store.reread()
        #expect(store.problem == "agents.custom[0].id \u{201C}codex\u{201D} is a built-in agent\u{2019}s id.")

        file.edit(#"{"agents":{"custom":[{"id":"My Aider"}]}}"#)
        await store.reread()
        #expect(store.problem?.contains("lowercase letters, digits and dashes") == true)

        file.edit(#"{"agents":{"custom":[{"name":"Aider"}]}}"#)
        await store.reread()
        #expect(store.problem == "agents.custom[0].id is missing.")
        #expect(store.settings.customAgents.isEmpty)
    }

    // MARK: - Types

    @Test func aTypedAgentTakesWhatItLeavesOutFromItsPreset() throws {
        let settings = try UserSettings.decode("""
            {"agents":{"custom":[{
              "id":"opencode-work","name":"OpenCode (Work)","type":"opencode",
              "environment":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:3457/v1"}
            }]}}
            """)

        let opencode = try #require(Agent.preset("opencode"))
        var expected = opencode.withID("opencode-work")
        expected.name = "OpenCode (Work)"
        expected.type = "opencode"
        expected.environment = opencode.environment?.merging(["ANTHROPIC_BASE_URL": "http://127.0.0.1:3457/v1"]) { $1 }
        #expect(settings.customAgents == [expected])
    }

    @Test func aTypedAgentIsWrittenWithOnlyWhatDiffersFromItsPreset() throws {
        var agent = try #require(Agent.preset("opencode")).withID("opencode-work")
        agent.type = "opencode"
        agent.name = "OpenCode (Work)"
        agent.resumeCommand = nil
        agent.environment?["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:3457/v1"
        var settings = UserSettings()
        settings.customAgents = [agent]

        let text = try settings.encoded()

        #expect(text.contains(#""ANTHROPIC_BASE_URL" : "http://127.0.0.1:3457/v1""#))
        #expect(!text.contains("OPENCODE_CLI_CONFIG_CONTENT"))
        #expect(!text.contains(#""command""#))
        #expect(!text.contains(#""session_lookup""#))
        #expect(text.contains(#""resume_command" : """#))
        // The cleared resume command comes back as empty, which runs afresh.
        let decoded = try #require(try UserSettings.decode(text).customAgents.first)
        #expect(decoded.resumeCommand == "")
        #expect(decoded.commandLine(session: "x", resuming: true) == "opencode")
    }

    @Test func aTypeThatIsNotAPresetIsAProblem() async {
        file.edit(#"{"agents":{"custom":[{"id":"mine","type":"aider"}]}}"#)

        await store.load()

        #expect(store.problem == "agents.custom[0].type \u{201C}aider\u{201D} is not a built-in agent: one of claude-code, codex, opencode, pi.")
    }

    @Test(arguments: ShowWhitespace.allCases)
    func showWhitespaceDecodesEveryMode(_ mode: ShowWhitespace) throws {
        let decoded = try UserSettings.decode(#"{"editor":{"show_whitespace":"\#(mode.rawValue)"}}"#)

        #expect(decoded.showWhitespace == mode)
    }

    @Test func showWhitespaceIsNoneWhenTheKeyOrTheObjectIsMissing() throws {
        #expect(try UserSettings.decode("{}").showWhitespace == .none)
        #expect(try UserSettings.decode(#"{"editor":{}}"#).showWhitespace == .none)
    }

    @Test func showWhitespaceIsWrittenOnlyWhenItIsNotNone() throws {
        var settings = UserSettings()
        #expect(!(try settings.encoded().contains("editor")))

        settings.showWhitespace = .trailing
        let text = try settings.encoded()
        #expect(text.contains(#""show_whitespace" : "trailing""#))
        #expect(try UserSettings.decode(text).showWhitespace == .trailing)
    }

    @Test func anUnknownShowWhitespaceIsAProblemThatNamesTheModes() async {
        file.edit(#"{"editor":{"show_whitespace":"selection"}}"#)

        await store.load()

        #expect(store.problem == "editor.show_whitespace \u{201C}selection\u{201D} is not one of none, trailing, all.")
    }

    @Test func wordWrapAndItsColumnDecode() throws {
        let decoded = try UserSettings.decode(#"{"editor":{"word_wrap":true,"wrap_column":80}}"#)

        #expect(decoded.wordWrap)
        #expect(decoded.wrapColumn == 80)
    }

    @Test func wordWrapIsOffAndTheColumnUnsetWhenTheKeysOrTheObjectAreMissing() throws {
        for text in ["{}", #"{"editor":{}}"#] {
            let decoded = try UserSettings.decode(text)
            #expect(!decoded.wordWrap)
            #expect(decoded.wrapColumn == nil)
        }
    }

    @Test func wordWrapIsWrittenOnlyWhenOn() throws {
        var settings = UserSettings()
        #expect(!(try settings.encoded().contains("word_wrap")))

        settings.wordWrap = true
        let text = try settings.encoded()
        #expect(text.contains(#""word_wrap" : true"#))
        #expect(try UserSettings.decode(text).wordWrap)
    }

    @Test func theColumnIsWrittenOnlyWhenSetAndStaysWhileWrapIsOff() throws {
        var settings = UserSettings()
        #expect(!(try settings.encoded().contains("wrap_column")))

        settings.wrapColumn = 100
        let text = try settings.encoded()
        #expect(text.contains(#""wrap_column" : 100"#))
        #expect(!text.contains("word_wrap"))
        let decoded = try UserSettings.decode(text)
        #expect(decoded.wrapColumn == 100)
        #expect(!decoded.wordWrap)
    }

    @Test(arguments: ["9", "0", "-80", "80.5", #""80""#, "true", "null"])
    func aBadWrapColumnIsAProblem(_ value: String) async {
        file.edit(#"{"editor":{"word_wrap":true,"wrap_column":\#(value)}}"#)

        await store.load()

        #expect(store.problem == "editor.wrap_column must be a whole number of at least 10.")
        #expect(store.settings.wrapColumn == nil)
    }

    @Test func aColumnOfExactlyTenIsAccepted() throws {
        #expect(try UserSettings.decode(#"{"editor":{"wrap_column":10}}"#).wrapColumn == 10)
    }

    @Test func agentTerminalsKeepLessScrollbackThanShellsByDefault() {
        let settings = UserSettings()

        #expect(settings.shellScrollbackLines == 10_000)
        #expect(settings.agentScrollbackLines < settings.shellScrollbackLines)
    }

    @Test func scrollbackDecodesAndIsWrittenOnlyWhenChanged() throws {
        let decoded = try UserSettings.decode(#"{"terminal":{"scrollback_lines":500,"agent_scrollback_lines":0}}"#)
        #expect(decoded.shellScrollbackLines == 500)
        #expect(decoded.agentScrollbackLines == 0)

        #expect(!(try UserSettings().encoded().contains("scrollback")))
        #expect(try UserSettings.decode(try decoded.encoded()) == decoded)
    }

    @Test func zeroScrollbackIsAcceptedAndMeansUnlimited() throws {
        let decoded = try UserSettings.decode(#"{"terminal":{"scrollback_lines":0}}"#)
        #expect(decoded.shellScrollbackLines == 0)
        #expect(try UserSettings.decode(try decoded.encoded()).shellScrollbackLines == 0)
    }

    @Test(arguments: ["-1", "1.5", #""10""#, "null"])
    func aBadScrollbackIsAProblem(_ value: String) async {
        file.edit(#"{"terminal":{"agent_scrollback_lines":\#(value)}}"#)

        await store.load()

        #expect(store.problem == "terminal.agent_scrollback_lines must be a whole number of at least 0.")
    }

    @Test func anExternalEditIsAppliedLive() async {
        await store.load()
        store.startWatching()

        file.edit(#"{"providers":{"anthropic":{"endpoint":"https://api.anthropic.com"}}}"#)
        await settle()

        #expect(store.settings.anthropicEndpoint == "https://api.anthropic.com")
    }

    @Test func deletingTheFileResetsEverythingLiveAndDoesNotMakeItAgain() async {
        file.edit(#"{"updates":{"check_automatically":false}}"#)
        await store.load()
        store.startWatching()

        file.edit(nil)
        await settle()

        #expect(store.settings == UserSettings())
        #expect(file.contents == nil)
        #expect(file.writes.isEmpty)
    }

    @Test func everyChangeIsReported() async {
        var told: [Bool] = []
        store.onChange = { told.append($0.checkForUpdatesAutomatically) }
        await store.load()
        store.startWatching()

        file.edit(#"{"updates":{"check_automatically":false}}"#)
        await settle()
        store.update { $0.checkForUpdatesAutomatically = true }

        #expect(told == [false, true])
    }

    // MARK: - Writing

    @Test func aChangeIsWrittenSparseWithTheSchemaFirst() async throws {
        await store.load()

        store.update {
            $0.customAgents = [Self.aider]
            $0.anthropicEndpoint = "https://api.anthropic.com"
        }
        await store.flushWrites()

        #expect(file.writes == [
            """
            {
              "$schema" : "\(UserSettings.schemaURL)",
              "agents" : {
                "custom" : [
                  {
                    "command" : "aider",
                    "environment" : {
                      "EDITOR" : "vi"
                    },
                    "id" : "aider",
                    "name" : "Aider"
                  }
                ]
              },
              "providers" : {
                "anthropic" : {
                  "endpoint" : "https://api.anthropic.com"
                }
              }
            }

            """,
        ])
    }

    @Test func whatIsWrittenReadsBackTheSame() async throws {
        var settings = UserSettings()
        settings.checkForUpdatesAutomatically = false
        settings.firstPromptTemplate = "/grill-me {prompt}"
        settings.customAgents = [
            Self.aider,
            Agent(
                id: "mine", name: "Mine", command: "mine {session}", planCommand: "mine --plan",
                promptArgument: "--prompt {prompt}", promptNeedsReturn: true, resumeCommand: "mine -r {session}",
                sessionLookup: "mine ls"
            ),
        ]
        settings.anthropicEndpoint = "https://api.anthropic.com"

        #expect(try UserSettings.decode(settings.encoded()) == settings)
        #expect(try UserSettings.decode(UserSettings().encoded()) == UserSettings())
        #expect(try UserSettings().encoded() == "{\n  \"$schema\" : \"\(UserSettings.schemaURL)\"\n}\n")
    }

    @Test func changesAreWrittenOnceTheyStop() async throws {
        await store.load()

        store.update { $0.firstPromptTemplate = "/" }
        store.update { $0.firstPromptTemplate = "/g" }
        store.update { $0.firstPromptTemplate = "/gr" }
        #expect(file.writes.isEmpty)

        await settle()

        #expect(file.writes.count == 1)
        #expect(try UserSettings.decode(file.writes[0]).firstPromptTemplate == "/gr")
        #expect(clock.sleeps.allSatisfy { $0 == UserSettingsStore.writeDelay })
    }

    @Test func ourOwnWriteComingBackIsIgnored() async {
        var changes = 0
        store.onChange = { _ in changes += 1 }
        await store.load()
        store.startWatching()

        store.update { $0.firstPromptTemplate = "/grill-me {prompt}" }
        await store.flushWrites()
        await settle()

        #expect(changes == 1)
        #expect(file.writes.count == 1)
        #expect(store.settings.firstPromptTemplate == "/grill-me {prompt}")
    }

    @Test func anEditBackToWhatWasLastWrittenIsStillApplied() async throws {
        await store.load()
        store.startWatching()
        store.update { $0.firstPromptTemplate = "one" }
        await store.flushWrites()
        let written = try #require(file.contents)

        file.edit(#"{"agents":{"first_prompt_template":"two"}}"#)
        await settle()
        file.edit(written)
        await settle()

        #expect(store.settings.firstPromptTemplate == "one")
    }

    @Test func aFileWithAProblemIsNeverWrittenOverAndFixingItWins() async throws {
        file.edit(#"{"agents": {"#)
        await store.load()
        store.startWatching()
        #expect(store.problem != nil)

        store.update { $0.firstPromptTemplate = "/x" }
        await store.flushWrites()

        // Somebody's edit in progress, left alone.
        #expect(file.writes.isEmpty)
        #expect(file.contents == #"{"agents": {"#)
        #expect(store.settings.firstPromptTemplate == "/x")

        file.edit(#"{"agents":{"first_prompt_template":"/y"}}"#)
        await settle()
        await store.flushWrites()

        #expect(store.problem == nil)
        #expect(store.settings.firstPromptTemplate == "/y")
        #expect(file.writes.isEmpty)
    }

    @Test func openingWithNoFileMakesOneThatIsOnlyItsSchema() async {
        await store.load()

        await store.createFileIfMissing()
        await store.createFileIfMissing()

        #expect(file.writes == ["{\n  \"$schema\" : \"\(UserSettings.schemaURL)\"\n}\n"])
    }

    @Test func openingLeavesAFileThatIsThereAlone() async {
        file.edit("{ broken")
        await store.load()

        await store.createFileIfMissing()

        #expect(file.writes.isEmpty)
        #expect(file.contents == "{ broken")
    }

    // MARK: - Migrating

    func seedOldState() async throws {
        let agent = Agent(id: "custom-6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Aider", command: "aider")
        try await state.save(
            AgentsSnapshot(custom: [agent], lastUsed: agent.id, firstPromptTemplate: "/grill-me {prompt}"),
            forKey: AgentsSnapshot.persistenceKey
        )
        try await state.save(NamingSnapshot(endpoint: "https://api.anthropic.com"), forKey: NamingSnapshot.persistenceKey)
    }

    @Test func theFirstLaunchMovesTheOldSettingsIntoTheFile() async throws {
        try await seedOldState()
        let updater = StubUpdaterClient(automaticallyChecksForUpdates: false)

        await store.load(migratingFrom: state, updater: updater)

        let written = try UserSettings.decode(try #require(file.contents))
        #expect(written == store.settings)
        #expect(written.checkForUpdatesAutomatically == false)
        #expect(written.firstPromptTemplate == "/grill-me {prompt}")
        #expect(written.anthropicEndpoint == "https://api.anthropic.com")
        #expect(written.customAgents.map(\.id) == ["custom-6f9619ff-8b86-d011-b42d-00c04fc964ff"])
        // Left where it was, unused.
        let old = try #require(try await state.load(AgentsSnapshot.self, forKey: AgentsSnapshot.persistenceKey))
        #expect(old.custom.count == 1)
    }

    @Test func migratingOnlyDefaultsWritesNoFile() async {
        await store.load(migratingFrom: state, updater: StubUpdaterClient())

        #expect(file.contents == nil)
    }

    @Test func migrationHappensOnceSoADeletedFileStaysDefaults() async throws {
        try await seedOldState()
        await store.load(migratingFrom: state, updater: nil)
        file.edit(nil)

        let relaunched = UserSettingsStore(file: file, clock: clock)
        await relaunched.load(migratingFrom: state, updater: nil)

        #expect(relaunched.settings == UserSettings())
        #expect(file.contents == nil)
    }

    @Test func aFileThatIsAlreadyThereIsNotMigratedOver() async throws {
        try await seedOldState()
        file.edit(#"{"agents":{"first_prompt_template":"mine"}}"#)

        await store.load(migratingFrom: state, updater: nil)

        #expect(store.settings.firstPromptTemplate == "mine")
        #expect(store.settings.customAgents.isEmpty)
        #expect(file.writes.isEmpty)
    }
}
