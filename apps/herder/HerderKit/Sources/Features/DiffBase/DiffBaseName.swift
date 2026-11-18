import Core

/// How a base is written on the trigger.
enum DiffBaseName {
    /// A SHA is shortened to what a person reads; anything else is as given.
    static func display(_ name: String) -> String {
        let isSHA = name.count == 40 && name.allSatisfy(\.isHexDigit)
        return isSHA ? String(name.prefix(7)) : name
    }

    static func warning(for base: GitDiffBase) -> String {
        "\(display(base.ref)) not found, showing uncommitted changes"
    }
}
