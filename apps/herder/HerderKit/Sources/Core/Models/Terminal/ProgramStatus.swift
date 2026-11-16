import Foundation

/// What a program running in a terminal says it is doing, in a program status
/// report (OSC 7501). The program's own word, unlike what Herder guesses from
/// its output.
///
/// A program may report on several things at once, one record each, told
/// apart by ``id``. The spec is at
/// https://www.superlogical.com/rex/docs/build/program-status
public struct ProgramStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// At rest, waiting for the next instruction.
        case idle
        case working
        /// Finished, with a result to look at.
        case done
        /// Can't go on until the person does something.
        case blocked
        /// Failed and stopped.
        case error
    }

    /// What a blocked program needs.
    public enum Need: Sendable, Equatable {
        case permission
        case question
        case auth
    }

    /// Which record this is. Empty for the program itself; a `/` makes one
    /// record the child of another, so `build/test` is beneath `build`.
    public var id: String
    public var state: State

    /// Only for ``State/blocked``, and only when the program said.
    public var need: Need?

    /// From 0 through 100, for ``State/working`` and ``State/blocked``, when
    /// the program gave one.
    public var progress: Int?

    /// A name a machine can match on, such as `opencode`. Taken from the
    /// nearest record above when the report had none.
    public var app: String

    /// A short label, to tell records apart. Empty when there was none.
    public var title: String

    /// One line saying what it is doing or waiting for. Empty when there was
    /// none. Untrusted text, with invisible formatting already taken out.
    public var message: String

    public init(
        id: String = "",
        state: State,
        need: Need? = nil,
        progress: Int? = nil,
        app: String = "",
        title: String = "",
        message: String = ""
    ) {
        self.id = id
        self.state = state
        self.need = need
        self.progress = progress
        self.app = app
        self.title = title
        self.message = message
    }

    /// Whether this record is `ancestor` or beneath it. Everything is beneath
    /// the empty id.
    public func isWithin(_ ancestor: String) -> Bool {
        ancestor.isEmpty || id == ancestor || id.hasPrefix(ancestor + "/")
    }
}
