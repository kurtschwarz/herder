//! Turning source text into a flat run of tokens.

use crate::kind::{self, Kind};
use crate::language::{self, Language};
use tree_sitter_highlight::{HighlightEvent, Highlighter};

/// A styled span of the source, in UTF-16 offsets.
///
/// UTF-16 because the only consumer is `NSTextStorage`, which indexes in UTF-16
/// code units. Tree-sitter counts bytes, so the conversion happens here rather
/// than in Swift: a caller that has to remember to convert is a caller that
/// will one day forget, and the symptom — colour sliding further off with each
/// non-ASCII character earlier in the file — looks like a highlighting bug
/// rather than an offset bug.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
#[repr(C)]
pub struct Token {
    pub start: u32,
    pub end: u32,
    pub kind: u32,
}

/// Anything longer is returned unhighlighted. The editor already refuses files
/// over 1 MB; this is the same ceiling restated where the parse happens, so a
/// later caller cannot hand over a 50 MB buffer and stall.
pub const MAX_BYTES: usize = 1_000_000;

/// Tokens for `source`, read as `language`.
///
/// Adjacent spans of the same kind are merged, and text carrying no kind is
/// dropped: the result is only what needs painting.
pub fn highlight(language: &'static Language, source: &str) -> Vec<Token> {
    if source.len() > MAX_BYTES {
        return Vec::new();
    }
    let Some(configuration) = language::configuration(language) else {
        return Vec::new();
    };

    let mut highlighter = Highlighter::new();
    let events = highlighter.highlight(
        configuration,
        source.as_bytes(),
        None,
        None,
        // An injected language that is not in the table — JavaScript inside
        // HTML, before the JavaScript row existed — leaves that span styled by
        // the outer grammar instead of failing the whole file.
        |name| language::by_name(name).and_then(language::configuration),
    );
    let Ok(events) = events else { return Vec::new() };

    // Highlights nest: a `@string` inside a `@comment` inside a doc comment.
    // The innermost is what a reader should see, so the top of the stack wins.
    let mut stack: Vec<Option<Kind>> = Vec::new();
    let mut tokens: Vec<Token> = Vec::new();

    for event in events {
        match event {
            // Starts and ends pair up: an unrecognized capture produces neither,
            // so pushing unconditionally here keeps the stack in step.
            Ok(HighlightEvent::HighlightStart(highlight)) => {
                stack.push(kind::styling(highlight.0));
            }
            Ok(HighlightEvent::HighlightEnd) => {
                stack.pop();
            }
            Ok(HighlightEvent::Source { start, end }) => {
                let Some(kind) = stack.last().copied().flatten() else {
                    continue;
                };
                if start < end {
                    push(&mut tokens, start as u32, end as u32, kind);
                }
            }
            // A cancelled or failed parse keeps what was already found. Most of
            // a highlighted file reads better than none of one.
            Err(_) => break,
        }
    }

    to_utf16(source, &mut tokens);
    tokens
}

/// Appends a span, extending the previous token instead when the two touch and
/// agree. Grammars emit an event per node, so without this one line of code
/// becomes a dozen identically styled tokens.
fn push(tokens: &mut Vec<Token>, start: u32, end: u32, kind: Kind) {
    if let Some(last) = tokens.last_mut()
        && last.end == start
        && last.kind == kind as u32
    {
        last.end = end;
        return;
    }
    tokens.push(Token {
        start,
        end,
        kind: kind as u32,
    });
}

/// Rewrites UTF-8 byte offsets as UTF-16 code-unit offsets, in place.
///
/// ASCII needs no work at all, which is why it is tested first: that test is a
/// fast scan and the walk below is not.
fn to_utf16(source: &str, tokens: &mut [Token]) {
    if source.is_ascii() {
        return;
    }
    let mut cursor = Utf16Cursor::new(source);
    for token in tokens {
        token.start = cursor.offset(token.start);
        token.end = cursor.offset(token.end);
    }
}

/// Converts byte offsets to UTF-16 offsets in one pass.
///
/// Tokens come out of the highlighter in order and never overlap, so every
/// offset asked for is at or after the one before and the walk never restarts.
struct Utf16Cursor<'a> {
    characters: std::str::CharIndices<'a>,
    pending: Option<(usize, char)>,
    utf16: u32,
}

impl<'a> Utf16Cursor<'a> {
    fn new(source: &'a str) -> Self {
        let mut characters = source.char_indices();
        let pending = characters.next();
        Self {
            characters,
            pending,
            utf16: 0,
        }
    }

    /// The UTF-16 offset of byte offset `target`, which must not be less than
    /// any offset already asked for.
    fn offset(&mut self, target: u32) -> u32 {
        while let Some((index, character)) = self.pending {
            if index as u32 >= target {
                break;
            }
            self.utf16 += character.len_utf16() as u32;
            self.pending = self.characters.next();
        }
        self.utf16
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::language::identify;

    fn language_of(file_name: &str, source: &str) -> &'static Language {
        language::language(identify(file_name, source))
            .unwrap_or_else(|| panic!("{file_name} matches no language"))
    }

    fn tokens(file_name: &str, source: &str) -> Vec<Token> {
        highlight(language_of(file_name, source), source)
    }

    fn kind_of(raw: u32) -> Kind {
        kind::CAPTURES
            .iter()
            .map(|(_, kind)| *kind)
            .find(|kind| *kind as u32 == raw)
            .expect("token carries a kind no capture produces")
    }

    /// The text a token covers, decoded back from UTF-16. Also checks that the
    /// offsets land on character boundaries.
    fn text_of(source: &str, token: &Token) -> String {
        let units: Vec<u16> = source.encode_utf16().collect();
        String::from_utf16(&units[token.start as usize..token.end as usize])
            .expect("token offsets do not land on character boundaries")
    }

    /// The kind painted over the first occurrence of `needle`.
    fn kind_at(file_name: &str, source: &str, needle: &str) -> Option<Kind> {
        let byte = source.find(needle).expect("needle is not in source");
        let offset = source[..byte].encode_utf16().count() as u32;
        tokens(file_name, source)
            .into_iter()
            .find(|token| token.start <= offset && offset < token.end)
            .map(|token| kind_of(token.kind))
    }

    #[test]
    fn swift_keywords_strings_and_comments_are_found() {
        let source = "// a note\nlet name = \"Herder\"\n";
        assert_eq!(kind_at("A.swift", source, "// a note"), Some(Kind::Comment));
        assert_eq!(kind_at("A.swift", source, "let"), Some(Kind::Keyword));
        assert_eq!(kind_at("A.swift", source, "\"Herder\""), Some(Kind::String));
    }

    #[test]
    fn rust_types_keywords_and_literals_are_found() {
        let source = "fn main() { let x: u32 = 42; }";
        assert_eq!(kind_at("m.rs", source, "fn"), Some(Kind::Keyword));
        assert_eq!(kind_at("m.rs", source, "u32"), Some(Kind::Type));
        // Rust's own query calls number literals `@constant.builtin`, not
        // `@number`. That is the grammar author's choice and this crate does
        // not second-guess it: the two are one colour family in the theme.
        assert_eq!(kind_at("m.rs", source, "42"), Some(Kind::Constant));
    }

    #[test]
    fn json_strings_and_numbers_are_distinguished() {
        let source = "{\"name\": 1}";
        assert_eq!(kind_at("p.json", source, "\"name\""), Some(Kind::String));
        assert_eq!(kind_at("p.json", source, "1"), Some(Kind::Number));
    }

    /// The distinctions worth having in an ignore file: what is a path, what is
    /// a metacharacter, and what is turned off.
    #[test]
    fn gitignore_separates_paths_from_the_characters_that_are_not_paths() {
        let source = "# a note\n*.log\n!keep.log\nbuild/\n";

        assert_eq!(kind_at(".gitignore", source, "# a note"), Some(Kind::Comment));
        assert_eq!(kind_at(".gitignore", source, "*"), Some(Kind::Escape));
        assert_eq!(kind_at(".gitignore", source, ".log"), Some(Kind::String));
        assert_eq!(kind_at(".gitignore", source, "!"), Some(Kind::Operator));
        assert_eq!(kind_at(".gitignore", source, "keep.log"), Some(Kind::String));
        assert_eq!(kind_at(".gitignore", source, "/"), Some(Kind::Punctuation));
    }

    /// Without a `string.special.path` row, `@string.special.path` falls back to
    /// `string.special` and every path in the file is painted as an escape.
    /// This is the test that catches that regression.
    #[test]
    fn a_gitignore_is_mostly_string_coloured() {
        let source = "node_modules/\ntarget/\n.build/\n";
        let found = tokens(".gitignore", source);
        let strings = found
            .iter()
            .filter(|token| token.kind == Kind::String as u32)
            .map(|token| (token.end - token.start) as usize)
            .sum::<usize>();

        assert!(
            strings * 2 > source.len(),
            "only {strings} of {} bytes are string-coloured",
            source.len()
        );
    }

    /// The grammar parses the parts of a glob, not just the line, so a
    /// character class comes out as the thing it is.
    #[test]
    fn gitignore_highlights_the_inside_of_a_character_class() {
        let source = "log.[[:digit:]]\n[Bb]in/\n";
        assert_eq!(kind_at(".gitignore", source, "digit"), Some(Kind::Type));
        assert_eq!(kind_at(".gitignore", source, "[[:"), Some(Kind::Punctuation));
        assert_eq!(kind_at(".gitignore", source, "Bb"), Some(Kind::String));
    }

    #[test]
    fn gitignore_escapes_are_not_part_of_the_path_around_them() {
        let source = "file\\ with\\ space.txt\n";
        assert_eq!(kind_at(".gitignore", source, "file"), Some(Kind::String));
        assert_eq!(kind_at(".gitignore", source, "\\ "), Some(Kind::Escape));
    }

    #[test]
    fn a_token_covers_exactly_the_text_it_styles() {
        let source = "let x = 1\n";
        let found = tokens("A.swift", source);
        let first = found.first().expect("no tokens");
        assert_eq!(text_of(source, first), "let");
    }

    #[test]
    fn tokens_are_ordered_and_do_not_overlap() {
        let source = include_str!("highlight.rs");
        let found = tokens("highlight.rs", source);
        assert!(found.len() > 50, "only {} tokens for this file", found.len());
        for token in &found {
            assert!(token.start < token.end, "empty token {token:?}");
        }
        for pair in found.windows(2) {
            assert!(
                pair[0].end <= pair[1].start,
                "{:?} overlaps {:?}",
                pair[0],
                pair[1]
            );
        }
    }

    #[test]
    fn adjacent_spans_of_one_kind_are_merged() {
        // `// one // two` on one line is a single comment token; on three lines
        // it is three, because the newlines between them carry no kind.
        let source = "// one\n// two\n// three\nlet x = 1\n";
        let comments = tokens("A.swift", source)
            .into_iter()
            .filter(|token| token.kind == Kind::Comment as u32)
            .count();
        assert_eq!(comments, 3);
    }

    #[test]
    fn offsets_are_utf16_so_text_after_an_emoji_is_still_right() {
        let source = "// 🐺🐺\nlet name = \"Herder\"\n";
        let string = tokens("A.swift", source)
            .into_iter()
            .find(|token| token.kind == Kind::String as u32)
            .expect("the string literal was not found");
        assert_eq!(text_of(source, &string), "\"Herder\"");
    }

    #[test]
    fn a_file_over_the_ceiling_is_not_parsed() {
        let source = format!("let x = 1\n{}", "/".repeat(MAX_BYTES));
        assert!(highlight(language_of("A.swift", &source), &source).is_empty());
    }

    #[test]
    fn markdown_highlights_inline_spans_through_its_injection() {
        // The inline grammar is reachable only by injection, so a kind inside
        // a paragraph proves the injection callback resolved it.
        let source = "# Title\n\nSome `code` here.\n";
        assert_eq!(kind_at("a.md", source, "code"), Some(Kind::String));
    }

    #[test]
    fn a_fenced_code_block_is_highlighted_as_the_language_it_names() {
        let source = "```rust\nlet x = 1;\n```\n";
        assert_eq!(kind_at("a.md", source, "let"), Some(Kind::Keyword));
        assert_eq!(kind_at("a.md", source, "1;"), Some(Kind::Constant));
        // The block as a whole is `@text.literal`, and markdown's `@none` on
        // its content is not recognized, so the gaps between Rust's own
        // highlights keep the block's colour. See the note in `kind.rs`.
        assert_eq!(kind_at("a.md", source, " x = "), Some(Kind::String));
    }

    #[test]
    fn an_annotation_capture_does_not_erase_a_real_one() {
        // Swift's query is `[(comment) (multiline_comment)] @comment @spell`,
        // and tree-sitter gives a node its last capture, so without `@spell`
        // being stripped this finds nothing.
        let source = "// a note\nlet x = 1\n";
        assert_eq!(kind_at("A.swift", source, "// a note"), Some(Kind::Comment));
    }

    /// A recipe body is a shell script and is most of what a justfile contains,
    /// so an injection that contributes nothing leaves the file looking almost
    /// unhighlighted. See `just_injections`.
    #[test]
    fn a_recipe_body_is_highlighted_as_the_shell_script_it_is() {
        let source = "build:\n    cargo build --release\n    echo \"done\"\n";
        assert_eq!(kind_at("justfile", source, "\"done\""), Some(Kind::String));
        assert_eq!(kind_at("justfile", source, "--release"), Some(Kind::Constant));
        // The recipe's own name still comes from just's grammar, not bash's.
        assert_eq!(kind_at("justfile", source, "build:"), Some(Kind::Function));
    }

    /// The shebang names an interpreter rather than a language, and just's
    /// `language` node includes the space in front of it, so this is what
    /// `by_name` has to cope with.
    #[test]
    fn a_shebang_recipe_is_highlighted_as_the_interpreter_it_names() {
        let python = "check:\n    #!/usr/bin/env python3\n    x = 1\n";
        assert_eq!(kind_at("justfile", python, "x = 1"), Some(Kind::Variable));

        let node = "check:\n    #!/usr/bin/env node\n    const x = 1\n";
        assert_eq!(kind_at("justfile", node, "const"), Some(Kind::Keyword));
    }

    #[test]
    fn javascript_inside_html_is_highlighted_through_its_injection() {
        let source = "<script>const x = 1</script>\n";
        assert_eq!(kind_at("a.html", source, "const"), Some(Kind::Keyword));
    }

    #[test]
    fn every_language_highlights_something() {
        // Keeps the table honest as it grows: a row whose queries compile but
        // produce nothing is a row that is silently not working.
        let samples: &[(&str, &str)] = &[
            ("a.sh", "# note\necho \"hi\"\n"),
            ("a.c", "/* note */\nint main(void) { return 0; }\n"),
            ("a.css", "/* note */\n.a { color: red; }\n"),
            (".gitignore", "# note\n*.log\n!keep.log\n"),
            ("a.go", "// note\npackage main\n"),
            ("a.html", "<!-- note --><p class=\"a\">hi</p>\n"),
            ("a.js", "// note\nconst x = 1\n"),
            ("a.json", "{\"a\": 1}\n"),
            ("justfile", "# note\nbuild:\n    cargo build\n"),
            ("a.md", "# Title\n\nSome `code` here.\n"),
            ("a.py", "# note\ndef f(): return 1\n"),
            ("a.rs", "// note\nfn main() {}\n"),
            ("a.swift", "// note\nlet x = 1\n"),
            ("a.toml", "# note\n[a]\nb = 1\n"),
            ("a.ts", "// note\nconst x: number = 1\n"),
            ("a.tsx", "const A = () => <p>hi</p>\n"),
            ("a.yml", "# note\na: 1\n"),
        ];

        for (file_name, source) in samples {
            assert!(
                !tokens(file_name, source).is_empty(),
                "{file_name} produced no tokens"
            );
        }
    }
}

