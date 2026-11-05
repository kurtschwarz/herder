//! The table of grammars, and how a file is matched to one.
//!
//! Adding a language is two edits: a dependency in `Cargo.toml` and a row in
//! `LANGUAGES`. Nothing else in this crate, and nothing at all on the Swift
//! side, needs to know the language exists.

use crate::kind;
use std::sync::{Mutex, OnceLock};
use tree_sitter_highlight::HighlightConfiguration;

/// A grammar and the files it claims.
pub struct Language {
    /// Shown to no one yet; used to resolve injections and to name failures.
    pub name: &'static str,

    /// Other names a grammar's `injections.scm` might call this language by.
    /// `#set! injection.language "js"` has to find the JavaScript row.
    pub aliases: &'static [&'static str],

    /// Lower-case, without the dot.
    pub extensions: &'static [&'static str],

    /// Whole file names, for the many build files that have no extension.
    /// Matched case-insensitively.
    pub filenames: &'static [&'static str],

    /// Interpreters that a `#!` line may name, for a script with neither a
    /// known extension nor a known name.
    pub interpreters: &'static [&'static str],

    /// Reachable through injection but never matched to a file of its own.
    /// Markdown's inline grammar parses spans inside a block tree and makes no
    /// sense applied to a whole document.
    pub injection_only: bool,

    grammar: fn() -> tree_sitter::Language,
    highlights: fn() -> String,
    injections: fn() -> String,
    locals: fn() -> String,
}

/// No language matched. Shared with Swift as the absent value, so it is 0 and
/// real languages are 1-based.
pub const NONE: u32 = 0;

const fn empty() -> String {
    String::new()
}

/// Every grammar linked into this crate.
///
/// Queries come out of the language crates as `&'static str` constants compiled
/// into the binary, so there is no resource bundle to find at runtime and no
/// `.scm` file to keep in step with its grammar.
pub static LANGUAGES: &[Language] = &[
    Language {
        name: "bash",
        aliases: &["sh", "shell", "zsh"],
        extensions: &["sh", "bash", "zsh", "zshrc", "bashrc", "zprofile", "bash_profile"],
        filenames: &[".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".profile"],
        interpreters: &["sh", "bash", "zsh", "dash", "ksh"],
        injection_only: false,
        grammar: || tree_sitter_bash::LANGUAGE.into(),
        highlights: || tree_sitter_bash::HIGHLIGHT_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "c",
        aliases: &[],
        extensions: &["c", "h"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_c::LANGUAGE.into(),
        highlights: || tree_sitter_c::HIGHLIGHT_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "css",
        aliases: &[],
        extensions: &["css"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_css::LANGUAGE.into(),
        highlights: || tree_sitter_css::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "gitignore",
        aliases: &[],
        extensions: &[],
        // One grammar covers the whole family: every one of these files is
        // git's ignore syntax, read by a different tool.
        filenames: &[
            ".gitignore",
            ".dockerignore",
            ".eslintignore",
            ".gcloudignore",
            ".helmignore",
            ".npmignore",
            ".prettierignore",
        ],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_gitignore::LANGUAGE.into(),
        highlights: || tree_sitter_gitignore::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "go",
        aliases: &[],
        extensions: &["go"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_go::LANGUAGE.into(),
        highlights: || tree_sitter_go::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "html",
        aliases: &[],
        extensions: &["html", "htm", "xhtml"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_html::LANGUAGE.into(),
        highlights: || tree_sitter_html::HIGHLIGHTS_QUERY.to_string(),
        injections: || tree_sitter_html::INJECTIONS_QUERY.to_string(),
        locals: empty,
    },
    Language {
        name: "javascript",
        aliases: &["js", "jsx"],
        extensions: &["js", "jsx", "mjs", "cjs"],
        filenames: &[],
        interpreters: &["node"],
        injection_only: false,
        grammar: || tree_sitter_javascript::LANGUAGE.into(),
        highlights: || {
            // The JSX patterns are a separate constant because the grammar can
            // be used without them. Herder reads whatever is on disk, so both.
            format!(
                "{}\n{}",
                tree_sitter_javascript::HIGHLIGHT_QUERY,
                tree_sitter_javascript::JSX_HIGHLIGHT_QUERY
            )
        },
        injections: || tree_sitter_javascript::INJECTIONS_QUERY.to_string(),
        locals: || tree_sitter_javascript::LOCALS_QUERY.to_string(),
    },
    Language {
        name: "json",
        aliases: &["jsonc"],
        extensions: &["json", "jsonc", "json5", "resolved", "webmanifest"],
        filenames: &[".babelrc", ".eslintrc", ".prettierrc", ".swcrc"],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_json::LANGUAGE.into(),
        highlights: || tree_sitter_json::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "just",
        aliases: &["justfile"],
        extensions: &["just"],
        filenames: &["justfile", ".justfile"],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_just::LANGUAGE.into(),
        highlights: || tree_sitter_just::HIGHLIGHTS_QUERY.to_string(),
        injections: just_injections,
        locals: empty,
    },
    Language {
        name: "markdown",
        aliases: &["md"],
        extensions: &["md", "markdown", "mdx"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_md::LANGUAGE.into(),
        highlights: || tree_sitter_md::HIGHLIGHT_QUERY_BLOCK.to_string(),
        injections: markdown_injections,
        locals: empty,
    },
    Language {
        name: "markdown_inline",
        aliases: &["markdown-inline"],
        extensions: &[],
        filenames: &[],
        interpreters: &[],
        injection_only: true,
        grammar: || tree_sitter_md::INLINE_LANGUAGE.into(),
        highlights: || tree_sitter_md::HIGHLIGHT_QUERY_INLINE.to_string(),
        injections: || tree_sitter_md::INJECTION_QUERY_INLINE.to_string(),
        locals: empty,
    },
    Language {
        name: "python",
        aliases: &["py"],
        extensions: &["py", "pyi", "pyw"],
        filenames: &[],
        interpreters: &["python", "python2", "python3"],
        injection_only: false,
        grammar: || tree_sitter_python::LANGUAGE.into(),
        highlights: || tree_sitter_python::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "rust",
        aliases: &["rs"],
        extensions: &["rs"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_rust::LANGUAGE.into(),
        highlights: || tree_sitter_rust::HIGHLIGHTS_QUERY.to_string(),
        injections: || tree_sitter_rust::INJECTIONS_QUERY.to_string(),
        locals: empty,
    },
    Language {
        name: "swift",
        aliases: &[],
        extensions: &["swift"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_swift::LANGUAGE.into(),
        highlights: || tree_sitter_swift::HIGHLIGHTS_QUERY.to_string(),
        injections: || tree_sitter_swift::INJECTIONS_QUERY.to_string(),
        locals: || tree_sitter_swift::LOCALS_QUERY.to_string(),
    },
    Language {
        name: "toml",
        aliases: &[],
        extensions: &["toml"],
        filenames: &["Cargo.lock"],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_toml_ng::LANGUAGE.into(),
        highlights: || tree_sitter_toml_ng::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
    Language {
        name: "tsx",
        aliases: &[],
        extensions: &["tsx"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_typescript::LANGUAGE_TSX.into(),
        highlights: typescript_highlights,
        injections: empty,
        locals: || tree_sitter_typescript::LOCALS_QUERY.to_string(),
    },
    Language {
        name: "typescript",
        aliases: &["ts"],
        extensions: &["ts", "mts", "cts"],
        filenames: &[],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into(),
        highlights: typescript_highlights,
        injections: empty,
        locals: || tree_sitter_typescript::LOCALS_QUERY.to_string(),
    },
    Language {
        name: "yaml",
        aliases: &["yml"],
        extensions: &["yaml", "yml"],
        filenames: &[".clang-format", ".clang-tidy"],
        interpreters: &[],
        injection_only: false,
        grammar: || tree_sitter_yaml::LANGUAGE.into(),
        highlights: || tree_sitter_yaml::HIGHLIGHTS_QUERY.to_string(),
        injections: empty,
        locals: empty,
    },
];

/// TypeScript's own query only covers what it adds to JavaScript, so the two
/// are concatenated. Both TypeScript and TSX use the result.
fn typescript_highlights() -> String {
    format!(
        "{}\n{}",
        tree_sitter_javascript::HIGHLIGHT_QUERY,
        tree_sitter_typescript::HIGHLIGHTS_QUERY
    )
}

/// Markdown is two grammars: one for block structure, one for the spans inside
/// a block, reached by injection. The bundled injection pattern for the inline
/// grammar does not set `injection.include-children`, and without it the
/// injected range comes out empty, because an `inline` node's text all belongs
/// to its children. The result is a document with headings and code fences
/// highlighted and every paragraph left plain.
///
/// A corrected pattern is appended rather than the bundled one edited: the
/// bundled pattern then matches first, contributes an empty range, and is
/// skipped, and this one makes the layer. Editing the bundled text would mean
/// matching on it, which would quietly stop working when it next changes.
fn markdown_injections() -> String {
    format!(
        "{}\n((inline) @injection.content\n  (#set! injection.language \"markdown_inline\")\n  (#set! injection.include-children))\n",
        tree_sitter_md::INJECTION_QUERY_BLOCK
    )
}

/// A justfile is mostly shell: the body of every recipe is a script, and the
/// grammar leaves it as one undifferentiated `recipe_body` for an injection to
/// claim. The bundled patterns claim it but do not set
/// `injection.include-children`, and without that the range comes out empty,
/// because a `recipe_body`'s text all belongs to its children. The result is a
/// file with its recipe names and settings highlighted and every recipe left
/// plain — which is most of what there is to read.
///
/// Corrected patterns are appended rather than the bundled ones edited, for the
/// reason given on [`markdown_injections`]: the bundled pattern matches first,
/// contributes an empty range and is skipped, and these make the layers.
fn just_injections() -> String {
    format!(
        "{}\n\
         ((recipe_body !shebang) @injection.content\n\
         \x20 (#set! injection.language \"bash\")\n\
         \x20 (#set! injection.include-children))\n\
         ((recipe_body (shebang (language) @injection.language)) @injection.content\n\
         \x20 (#set! injection.include-children))\n",
        tree_sitter_just::INJECTIONS_QUERY
    )
}

/// Capture names that annotate rather than style.
///
/// `tree-sitter-highlight` gives a node the *last* capture that matches it, so
/// `(comment) @comment @spell` paints nothing at all: `@spell` wins and means
/// nothing here. These come from nvim-treesitter, where they drive spell
/// checking and concealment, and removing them lets the real capture through.
///
/// `@none` is deliberately not in this list. It means "clear whatever is
/// underneath", which markdown relies on to stop a fenced block's literal
/// styling bleeding through the code inside it, so it is recognized and
/// handled as a kind of its own.
const NOOP_CAPTURES: &[&str] = &["spell", "nospell", "conceal"];

/// Removes the annotation captures above from a query.
///
/// Scans rather than pattern-matches because `@` is ordinary text inside a
/// query's string literals — CSS's `"@media"`, for one — and a blind
/// find-and-replace would corrupt them.
fn strip_noop_captures(query: &str) -> String {
    let mut out = String::with_capacity(query.len());
    let mut rest = query;

    while let Some(index) = rest.find(['@', '"', ';']) {
        let (before, from) = rest.split_at(index);
        out.push_str(before);

        let mut characters = from.char_indices();
        let (_, marker) = characters.next().expect("find returned a valid index");
        match marker {
            // A string literal, to its closing quote, escapes and all.
            '"' => {
                let mut escaped = false;
                let end = characters
                    .find(|(_, character)| {
                        let closes = *character == '"' && !escaped;
                        escaped = *character == '\\' && !escaped;
                        closes
                    })
                    .map_or(from.len(), |(index, character)| index + character.len_utf8());
                out.push_str(&from[..end]);
                rest = &from[end..];
            }
            // A comment, to the end of its line.
            ';' => {
                let end = from.find('\n').map_or(from.len(), |index| index + 1);
                out.push_str(&from[..end]);
                rest = &from[end..];
            }
            // A capture: `@` and then its dotted name.
            _ => {
                let end = characters
                    .find(|(_, character)| {
                        !character.is_ascii_alphanumeric() && !"_.-".contains(*character)
                    })
                    .map_or(from.len(), |(index, _)| index);
                if !NOOP_CAPTURES.contains(&&from[1..end]) {
                    out.push_str(&from[..end]);
                }
                rest = &from[end..];
            }
        }
    }

    out.push_str(rest);
    out
}

/// Which language a file is written in, or [`NONE`].
///
/// Extension first, because it is right nearly always and costs nothing. Then
/// the whole file name, which is how `Dockerfile` and `justfile` are caught.
/// Then the `#!` line, the only evidence an extensionless script leaves.
pub fn identify(file_name: &str, source: &str) -> u32 {
    let name = file_name.rsplit('/').next().unwrap_or(file_name);

    // Extensions are taken longest-first so `.d.ts` and `.tar.gz` style
    // compound suffixes have somewhere to go later without this changing.
    if let Some((_, extension)) = name.rsplit_once('.') {
        let extension = extension.to_ascii_lowercase();
        if let Some(id) = find(|language| language.extensions.contains(&extension.as_str())) {
            return id;
        }
    }

    let lowered = name.to_ascii_lowercase();
    if let Some(id) = find(|language| {
        language
            .filenames
            .iter()
            .any(|candidate| candidate.to_ascii_lowercase() == lowered)
    }) {
        return id;
    }

    interpreter(source)
        .and_then(|interpreter| {
            find(|language| language.interpreters.contains(&interpreter.as_str()))
        })
        .unwrap_or(NONE)
}

/// The command a `#!` line runs, bare of its path. `#!/usr/bin/env -S python3 -u`
/// gives `python3`: `env` is a launcher, not an interpreter, so its switches are
/// skipped and the first word that is not one is taken.
fn interpreter(source: &str) -> Option<String> {
    let line = source.lines().next()?.strip_prefix("#!")?;
    let mut words = line
        .split_whitespace()
        .map(|word| word.rsplit('/').next().unwrap_or(word));

    let first = words.next()?;
    if first != "env" {
        return Some(first.to_ascii_lowercase());
    }
    words
        .find(|word| !word.starts_with('-') && !word.contains('='))
        .map(str::to_ascii_lowercase)
}

/// The 1-based id of the first language satisfying `predicate`, skipping the
/// ones that only exist to be injected.
fn find(predicate: impl Fn(&Language) -> bool) -> Option<u32> {
    LANGUAGES
        .iter()
        .position(|language| !language.injection_only && predicate(language))
        .map(|index| index as u32 + 1)
}

/// The language `id` names, or `None` for [`NONE`] and anything out of range.
pub fn language(id: u32) -> Option<&'static Language> {
    LANGUAGES.get(id.checked_sub(1)? as usize)
}

/// Compiles every grammar's queries, so the first file opened does not pay for
/// it.
///
/// Worth a function of its own because the cost is not what you would guess.
/// Compiling a query means analysing it against the grammar's state machine, so
/// the price tracks the size of the *grammar*, not the query: Swift's
/// `parser.c` is 23 MB and its 421-byte `locals.scm` takes 96 ms, where JSON's
/// whole configuration takes 50 µs. Swift alone is 260 ms, and that is 260 ms
/// of a reader waiting to see a file they have just clicked.
///
/// Highlighting is a few hundred microseconds once this is done, so the whole
/// perceived cost of the feature is this call. Make it early, off whatever
/// thread the reader is waiting on.
pub fn warm() {
    for language in LANGUAGES {
        configuration(language);
    }
}

/// The language a grammar's injection query calls `name`.
///
/// A name can arrive as the raw text of a captured node rather than as a
/// literal in the query, so it is trimmed: just's `language` node spans the
/// whitespace after the `#!` command, which makes the injected language
/// ` python3` and matches nothing.
///
/// Falling back to the interpreters is for the same recipes, which inject the
/// interpreter the `#!` line names rather than a language: the name arrives as
/// `python3` or `node`, not `python` or `javascript`. Those spellings are
/// already enumerated as `interpreters`, so they are reused here instead of
/// being restated as aliases of every language a script can be written in.
pub fn by_name(name: &str) -> Option<&'static Language> {
    let name = name.trim().to_ascii_lowercase();
    LANGUAGES
        .iter()
        .find(|language| language.name == name || language.aliases.contains(&name.as_str()))
        .or_else(|| {
            LANGUAGES
                .iter()
                .find(|language| language.interpreters.contains(&name.as_str()))
        })
}

/// Query compilation is slow enough to matter and its result never changes, so
/// each configuration is built once and kept for the life of the process.
///
/// `HighlightConfiguration` is documented as shareable between threads, so a
/// leaked reference can be handed to any caller. There is one per grammar and
/// they are wanted until exit, so nothing is lost by never freeing them.
static CONFIGS: OnceLock<Mutex<Vec<Option<&'static HighlightConfiguration>>>> = OnceLock::new();

/// The compiled queries for a language, or `None` if they do not compile.
///
/// A query that fails is a bug in this crate or in a language crate, not
/// something a reader can act on, so the file is left unhighlighted rather than
/// reported. Release builds swallow it; debug builds trip an assertion.
pub fn configuration(language: &'static Language) -> Option<&'static HighlightConfiguration> {
    let index = LANGUAGES
        .iter()
        .position(|candidate| std::ptr::eq(candidate, language))
        .expect("language is not from LANGUAGES");

    let cache = CONFIGS.get_or_init(|| Mutex::new(vec![None; LANGUAGES.len()]));
    let mut cache = cache.lock().expect("syntax configuration cache poisoned");
    if let Some(configuration) = cache[index] {
        return Some(configuration);
    }

    let built = build(language)?;
    cache[index] = Some(built);
    Some(built)
}

fn build(language: &'static Language) -> Option<&'static HighlightConfiguration> {
    let mut configuration = HighlightConfiguration::new(
        (language.grammar)(),
        language.name,
        &strip_noop_captures(&(language.highlights)()),
        &(language.injections)(),
        &(language.locals)(),
    )
    .map_err(|error| {
        debug_assert!(false, "{} queries do not compile: {error}", language.name);
        error
    })
    .ok()?;

    configuration.configure(&kind::names());
    Some(Box::leak(Box::new(configuration)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn name_of(id: u32) -> Option<&'static str> {
        language(id).map(|language| language.name)
    }

    #[test]
    fn none_is_zero_and_resolves_to_nothing() {
        assert_eq!(NONE, 0);
        assert!(language(NONE).is_none());
    }

    #[test]
    fn every_grammar_compiles_its_queries() {
        for language in LANGUAGES {
            assert!(
                configuration(language).is_some(),
                "{} has queries that do not compile",
                language.name
            );
        }
    }

    #[test]
    fn names_and_aliases_are_unique() {
        let mut seen = std::collections::HashSet::new();
        for language in LANGUAGES {
            assert!(seen.insert(language.name), "duplicate name {}", language.name);
            for alias in language.aliases {
                assert!(
                    seen.insert(alias),
                    "{} claims {alias}, which is taken",
                    language.name
                );
            }
        }
    }

    #[test]
    fn an_extension_identifies_a_language() {
        assert_eq!(name_of(identify("main.rs", "")), Some("rust"));
        assert_eq!(name_of(identify("AppModel.swift", "")), Some("swift"));
        assert_eq!(name_of(identify("App.TSX", "")), Some("tsx"));
        assert_eq!(name_of(identify("/code/api/go.mod", "")), None);
    }

    #[test]
    fn a_whole_file_name_identifies_a_language() {
        assert_eq!(name_of(identify("Cargo.lock", "")), Some("toml"));
        assert_eq!(name_of(identify("/code/api/.prettierrc", "")), Some("json"));
    }

    /// Every tool that borrowed git's ignore syntax gets git's grammar. Cheap,
    /// because it is the same row.
    #[test]
    fn the_whole_ignore_file_family_is_one_language() {
        for name in [
            ".gitignore",
            ".dockerignore",
            ".npmignore",
            ".prettierignore",
            ".eslintignore",
            ".helmignore",
            ".gcloudignore",
        ] {
            assert_eq!(name_of(identify(name, "")), Some("gitignore"), "{name}");
        }
        // Nested, which is how most of them appear.
        assert_eq!(
            name_of(identify("/code/api/packages/web/.gitignore", "")),
            Some("gitignore")
        );
    }

    /// A justfile is known by its name in any of the casings `just` itself
    /// accepts, and a module by its `.just` extension.
    #[test]
    fn every_spelling_of_a_justfile_is_recognized() {
        for name in ["justfile", "Justfile", "JUSTFILE", ".justfile"] {
            assert_eq!(name_of(identify(name, "")), Some("just"), "{name}");
        }
        assert_eq!(name_of(identify("/code/api/justfile", "")), Some("just"));
        assert_eq!(name_of(identify("deploy.just", "")), Some("just"));
    }

    /// Justfile shebang recipes inject their interpreter, and just's `language`
    /// node takes in the space before it, so both have to resolve.
    #[test]
    fn an_injection_can_name_a_language_by_its_interpreter() {
        assert_eq!(by_name(" python3").map(|l| l.name), Some("python"));
        assert_eq!(by_name("node").map(|l| l.name), Some("javascript"));
        // A name or alias still wins, and an unknown name still resolves to
        // nothing rather than to the first language with a loose match.
        assert_eq!(by_name("bash").map(|l| l.name), Some("bash"));
        assert_eq!(by_name("zsh").map(|l| l.name), Some("bash"));
        assert_eq!(by_name("fish").map(|l| l.name), None);
    }

    #[test]
    fn an_extension_beats_a_file_name() {
        // `.clang-format` is YAML by name; a file called `x.clang-format.json`
        // is JSON by extension.
        assert_eq!(name_of(identify(".clang-format", "")), Some("yaml"));
        assert_eq!(name_of(identify("x.clang-format.json", "")), Some("json"));
    }

    #[test]
    fn a_shebang_identifies_a_language_with_no_extension() {
        assert_eq!(name_of(identify("release", "#!/bin/bash\nset -e\n")), Some("bash"));
        assert_eq!(
            name_of(identify("migrate", "#!/usr/bin/env -S python3 -u\n")),
            Some("python")
        );
        assert_eq!(name_of(identify("notes", "plain text\n")), None);
    }

    #[test]
    fn an_unknown_file_identifies_nothing() {
        assert_eq!(identify("notes.txt", "hello"), NONE);
        assert_eq!(identify("", ""), NONE);
    }

    #[test]
    fn an_annotation_capture_is_stripped_and_the_real_one_kept() {
        assert_eq!(
            strip_noop_captures("[(comment)] @comment @spell\n"),
            "[(comment)] @comment \n"
        );
        assert_eq!(strip_noop_captures("(x) @nospell"), "(x) ");
        assert_eq!(strip_noop_captures("(x) @conceal"), "(x) ");
    }

    #[test]
    fn a_clearing_capture_is_left_alone() {
        assert_eq!(strip_noop_captures("(x) @none"), "(x) @none");
    }

    #[test]
    fn an_at_sign_inside_a_string_or_comment_is_untouched() {
        // CSS captures `"@media"` as a keyword, so a find-and-replace over the
        // query text would break the grammar rather than the annotation.
        assert_eq!(strip_noop_captures(r#"["@spell"] @keyword"#), r#"["@spell"] @keyword"#);
        assert_eq!(strip_noop_captures("; see @spell\n(x) @y"), "; see @spell\n(x) @y");
        assert_eq!(
            strip_noop_captures(r#"(#match? @x "\"@spell") @spell"#),
            r#"(#match? @x "\"@spell") "#
        );
    }

    #[test]
    fn a_query_with_nothing_to_strip_comes_back_unchanged() {
        for language in LANGUAGES {
            let query = (language.highlights)();
            if !NOOP_CAPTURES
                .iter()
                .any(|name| query.contains(&format!("@{name}")))
            {
                assert_eq!(strip_noop_captures(&query), query, "{} changed", language.name);
            }
        }
    }

    #[test]
    fn an_injection_only_grammar_is_never_matched_to_a_file() {
        for language in LANGUAGES.iter().filter(|language| language.injection_only) {
            assert!(language.extensions.is_empty());
            assert!(language.filenames.is_empty());
            assert!(language.interpreters.is_empty());
        }
        assert!(by_name("markdown_inline").is_some());
    }
}
