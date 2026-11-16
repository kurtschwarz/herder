import Testing

@testable import SettingsFeature

@Suite struct EnvironmentVariableTests {
    @Test func rowsComeSortedByName() {
        let rows = EnvironmentVariable.rows(from: ["B": "2", "A": "1"])

        #expect(rows.map(\.name) == ["A", "B"])
        #expect(rows.map(\.value) == ["1", "2"])
    }

    @Test func noEnvironmentIsNoRowsAndNoRowsIsNoEnvironment() {
        #expect(EnvironmentVariable.rows(from: nil).isEmpty)
        #expect(EnvironmentVariable.dictionary(from: []) == nil)
    }

    @Test func rowsRoundTrip() {
        let environment = ["ANTHROPIC_BASE_URL": "http://localhost:4000", "_X1": ""]

        #expect(EnvironmentVariable.dictionary(from: EnvironmentVariable.rows(from: environment)) == environment)
    }

    @Test func aRowWithNoNameSetsNothing() {
        let rows = [EnvironmentVariable(name: "", value: "x"), EnvironmentVariable(name: "  ", value: "y")]

        #expect(EnvironmentVariable.dictionary(from: rows) == nil)
    }

    @Test func aRowWithAnInvalidNameSetsNothing() {
        let rows = ["1A", "A-B", "A B", "A=B", "é"].map { EnvironmentVariable(name: $0, value: "x") }

        #expect(EnvironmentVariable.dictionary(from: rows) == nil)
        #expect(rows.allSatisfy { !$0.hasValidName })
    }

    @Test func theLastOfTwoRowsWithTheSameNameWins() {
        let rows = [EnvironmentVariable(name: "A", value: "1"), EnvironmentVariable(name: "A", value: "2")]

        #expect(EnvironmentVariable.dictionary(from: rows) == ["A": "2"])
    }

    @Test func aNameIsTrimmedButAValueIsNot() {
        let rows = [EnvironmentVariable(name: " A ", value: " 1 ")]

        #expect(EnvironmentVariable.dictionary(from: rows) == ["A": " 1 "])
    }
}
