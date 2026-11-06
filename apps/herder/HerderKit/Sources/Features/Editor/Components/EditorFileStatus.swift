import SwiftUI

/// What the status bar says about the file showing: its encoding and language.
/// Plain text, like the breadcrumb: it reports, and nothing in it is clickable.
/// Empty when there is no text showing, because a file that is not shown has
/// no encoding worth stating. Always UTF-8, because that is the only thing a
/// file is read as.
public struct EditorFileStatus: View {
    private let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var body: some View {
        if case .text = model.content {
            Text("UTF-8")
            Text(model.language ?? "Plain Text")
        }
    }
}
