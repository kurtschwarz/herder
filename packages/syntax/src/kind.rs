//! The semantic kinds a token can have, and the capture names that produce them.
//!
//! Kinds are deliberately coarse. A theme has to give every one of them a
//! colour, and a reader cannot tell forty shades apart, so the list stops at the
//! distinctions that are worth drawing. Swift's `SyntaxTokenKind` mirrors these
//! raw values; `hdr_kind_count` lets a test catch the two drifting apart.

/// Keep in step with `SyntaxTokenKind` in the `Syntax` Swift module.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum Kind {
    Comment = 0,
    Keyword = 1,
    Operator = 2,
    Punctuation = 3,
    String = 4,
    Escape = 5,
    Number = 6,
    Constant = 7,
    Function = 8,
    Type = 9,
    Constructor = 10,
    Variable = 11,
    Property = 12,
    Parameter = 13,
    Attribute = 14,
    Tag = 15,
    Namespace = 16,
    Label = 17,
}

/// One more than the largest discriminant above.
pub const KIND_COUNT: u32 = 18;

/// Tree-sitter capture names, each paired with the kind it paints.
///
/// This is the whole of the "general system": `HighlightConfiguration::configure`
/// matches a capture against the longest entry here whose dotted parts are all
/// present in it, so `@keyword.control.conditional` finds `keyword` and
/// `@function.method.builtin` finds `function.builtin`. A grammar nobody has
/// thought about is therefore coarsely styled rather than unstyled, and
/// refining it means adding a more specific row — never editing the grammar.
///
/// Order is irrelevant to matching; it is alphabetical so a duplicate is easy to
/// spot.
pub const CAPTURES: &[(&str, Kind)] = &[
    ("attribute", Kind::Attribute),
    ("boolean", Kind::Constant),
    ("character", Kind::String),
    ("character.special", Kind::Escape),
    ("comment", Kind::Comment),
    ("constant", Kind::Constant),
    ("constant.builtin", Kind::Constant),
    ("constructor", Kind::Constructor),
    ("embedded", Kind::Variable),
    ("escape", Kind::Escape),
    ("float", Kind::Number),
    ("function", Kind::Function),
    ("function.builtin", Kind::Function),
    ("function.macro", Kind::Attribute),
    ("function.method", Kind::Function),
    ("include", Kind::Keyword),
    ("keyword", Kind::Keyword),
    ("label", Kind::Label),
    ("method", Kind::Function),
    ("module", Kind::Namespace),
    ("namespace", Kind::Namespace),
    ("number", Kind::Number),
    ("operator", Kind::Operator),
    ("parameter", Kind::Parameter),
    ("preproc", Kind::Keyword),
    ("property", Kind::Property),
    ("punctuation", Kind::Punctuation),
    ("string", Kind::String),
    ("string.escape", Kind::Escape),
    ("string.special", Kind::Escape),
    // A path is ordinary text, not a metacharacter. Without this row the
    // longest match for `@string.special.path` is `string.special`, and nearly
    // every character of a `.gitignore` — the paths themselves — comes out the
    // colour reserved for `\n` and `*`.
    ("string.special.path", Kind::String),
    ("tag", Kind::Tag),
    ("tag.attribute", Kind::Attribute),
    ("text.literal", Kind::String),
    ("text.reference", Kind::Constant),
    ("text.title", Kind::Function),
    ("text.uri", Kind::Label),
    ("type", Kind::Type),
    ("type.builtin", Kind::Type),
    ("variable", Kind::Variable),
    ("variable.builtin", Kind::Constant),
    ("variable.member", Kind::Property),
    ("variable.parameter", Kind::Parameter),
];

// `@none` is absent from the table on purpose, and the reason is worth keeping.
//
// nvim-treesitter uses it to clear whatever a node sits inside: a markdown
// fenced block is `@text.literal` as a whole, and `@none` on its content is how
// nvim stops that styling reaching the code inside. Recognizing it here made
// things worse rather than better.
//
// `tree-sitter-highlight` flattens every injected layer into one event stream,
// and that stream carries no layer identity. When two layers open a highlight at
// the same byte — the markdown `@none` and the injected Rust `@keyword` both
// start at the `l` of `let` — their end events come back interleaved, and a
// consumer reading the stream as one stack attributes them to each other's
// spans. Recognizing `@none` therefore cleared the keyword it was meant to sit
// behind.
//
// Left unrecognized, no event is emitted for it, and unstyled text inside a
// fenced block keeps the block's literal colour. Code in a fence reading as
// faintly literal is a reasonable thing to see; a keyword in it vanishing is
// not.

/// The capture names, in the order `Highlight` indices refer to.
pub fn names() -> Vec<&'static str> {
    CAPTURES.iter().map(|(name, _)| *name).collect()
}

/// The kind a `Highlight` index paints.
///
/// `None` for an index outside the table, which cannot arise from a configured
/// query but keeps a malformed one from being a panic.
pub fn styling(index: usize) -> Option<Kind> {
    CAPTURES.get(index).map(|(_, kind)| *kind)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn capture_names_are_unique() {
        let mut seen = HashSet::new();
        for name in names() {
            assert!(seen.insert(name), "duplicate capture name: {name}");
        }
    }

    #[test]
    fn capture_names_are_sorted() {
        let names: Vec<_> = CAPTURES.iter().map(|(name, _)| *name).collect();
        let mut sorted = names.clone();
        sorted.sort_unstable();
        assert_eq!(names, sorted, "CAPTURES is not in alphabetical order");
    }

    #[test]
    fn every_recognized_capture_paints_and_nothing_else_does() {
        for index in 0..CAPTURES.len() {
            assert!(styling(index).is_some());
        }
        assert_eq!(styling(CAPTURES.len()), None);
        assert!(!names().contains(&"none"), "see the note above `names`");
    }

    #[test]
    fn kind_count_covers_every_kind() {
        for (_, kind) in CAPTURES {
            assert!((*kind as u32) < KIND_COUNT);
        }
    }
}
