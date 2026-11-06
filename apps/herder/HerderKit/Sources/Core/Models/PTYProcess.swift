/// A process running in a terminal.
public struct PTYProcess: Sendable, Equatable {
    public var id: Int32

    /// The program's name: the last component of its `argv[0]`, without the
    /// dash that marks a login shell.
    public var name: String

    /// What was typed, as far as the process can say: its name, then its
    /// arguments. What a tab shows for it.
    public var commandLine: String

    /// This is the process the terminal started, and not something it ran. A
    /// terminal whose foreground process is its shell is idle.
    public var isShell: Bool

    public init(id: Int32, name: String, commandLine: String, isShell: Bool) {
        self.id = id
        self.name = name
        self.commandLine = commandLine
        self.isShell = isShell
    }
}
