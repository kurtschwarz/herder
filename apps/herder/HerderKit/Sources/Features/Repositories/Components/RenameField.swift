import DesignSystem
import SwiftUI

/// Edits a name in place. Return or clicking away keeps the edit, Escape drops
/// it; a blank name is the store's to refuse.
struct RenameField: View {
    let weight: Font.Weight
    let commit: (String) -> Void

    @State private var text: String
    @State private var isFinished = false
    @FocusState private var isFocused: Bool

    init(name: String, weight: Font.Weight = .semibold, commit: @escaping (String) -> Void) {
        _text = State(initialValue: name)
        self.weight = weight
        self.commit = commit
    }

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(Theme.Palette.text)
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onSubmit { finish(with: text) }
            .onExitCommand { finish(with: nil) }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish(with: text) }
            }
    }

    /// Submitting removes the field, which drops focus, which would commit a
    /// second time: `isFinished` makes the first outcome the only one.
    private func finish(with name: String?) {
        guard !isFinished else { return }
        isFinished = true
        commit(name ?? "")
    }
}
