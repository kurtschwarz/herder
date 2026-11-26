import SwiftUI

/// The Phosphor icons the app draws, from `Icons.xcassets`.
///
/// Only these, rather than the PhosphorSwift package, whose catalog of every
/// icon in every weight was most of the app's size. To add one, copy its
/// `.imageset` into `Icons.xcassets` from
/// `Sources/PhosphorSwift/Resources/Assets.xcassets/SVG/` at tag `2.1.0` of
/// https://github.com/phosphor-icons/swift, where every icon here came from,
/// and add a property for it. A name with no weight is the regular one.
public enum Ph {
    public static var archive: Image { icon("archive") }
    public static var arrowClockwise: Image { icon("arrow-clockwise") }
    public static var arrowsInLineVertical: Image { icon("arrows-in-line-vertical") }
    public static var caretDown: Image { icon("caret-down") }
    public static var caretDownBold: Image { icon("caret-down-bold") }
    public static var caretRightBold: Image { icon("caret-right-bold") }
    public static var caretUpDown: Image { icon("caret-up-down") }
    public static var chatCenteredDots: Image { icon("chat-centered-dots") }
    public static var checkBold: Image { icon("check-bold") }
    public static var clipboardText: Image { icon("clipboard-text") }
    public static var code: Image { icon("code") }
    public static var dotsThree: Image { icon("dots-three") }
    public static var file: Image { icon("file") }
    public static var folderSimpleDuotone: Image { icon("folder-simple-duotone") }
    public static var folderSimplePlus: Image { icon("folder-simple-plus") }
    public static var gearSixFill: Image { icon("gear-six-fill") }
    public static var gitBranch: Image { icon("git-branch") }
    public static var gitCommit: Image { icon("git-commit") }
    public static var gitDiff: Image { icon("git-diff") }
    public static var gitFork: Image { icon("git-fork") }
    public static var hammer: Image { icon("hammer") }
    public static var magnifyingGlass: Image { icon("magnifying-glass") }
    public static var notepad: Image { icon("notepad") }
    public static var plugsConnected: Image { icon("plugs-connected") }
    public static var plus: Image { icon("plus") }
    public static var pushPinFill: Image { icon("push-pin-fill") }
    public static var sparkle: Image { icon("sparkle") }
    public static var sparkleFill: Image { icon("sparkle-fill") }
    public static var tag: Image { icon("tag") }
    public static var terminal: Image { icon("terminal") }
    public static var trash: Image { icon("trash") }
    public static var warningFill: Image { icon("warning-fill") }
    public static var xBold: Image { icon("x-bold") }

    private static func icon(_ name: String) -> Image {
        Image(name, bundle: .module)
            .interpolation(.medium)
            .resizable()
    }
}
