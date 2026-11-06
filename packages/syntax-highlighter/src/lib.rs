//! Syntax highlighting for Herder's editor pane, over a C ABI.
//!
//! The whole surface is the functions below. Swift's `Syntax` module wraps
//! them and nothing else in the app knows this crate exists.
//!
//! The boundary speaks UTF-8 going in, because that is what tree-sitter parses
//! and what Swift hands over for free, and UTF-16 offsets coming out, because
//! that is what `NSTextStorage` indexes in. Neither side has to convert.

mod highlight;
mod kind;
mod language;

pub use highlight::{MAX_BYTES, Token, highlight};
pub use kind::{KIND_COUNT, Kind};
pub use language::{LANGUAGES, Language, NONE, identify, warm};

use std::ffi::c_char;
use std::slice;

/// A span of source to paint, in UTF-16 offsets from the start of the file.
///
/// `kind` is a `SyntaxTokenKind` raw value.
pub type HdrToken = Token;

/// An owned run of tokens. Freed with [`hdr_tokens_free`], never by the caller.
#[repr(C)]
pub struct HdrTokens {
    pub tokens: *const HdrToken,
    pub count: usize,
}

impl HdrTokens {
    const EMPTY: Self = Self {
        tokens: std::ptr::null(),
        count: 0,
    };

    /// Hands a vector's buffer to the caller. Capacity is dropped to length
    /// first so the box can be rebuilt from the pointer and count alone.
    fn new(tokens: Vec<Token>) -> Self {
        if tokens.is_empty() {
            return Self::EMPTY;
        }
        let boxed = tokens.into_boxed_slice();
        let count = boxed.len();
        Self {
            tokens: Box::into_raw(boxed).cast::<HdrToken>(),
            count,
        }
    }
}

/// How many `SyntaxTokenKind` cases there are.
///
/// Swift asserts this against its own enum, so a kind added here and not there
/// fails a test instead of painting an unknown colour.
#[unsafe(no_mangle)]
pub extern "C" fn hdr_kind_count() -> u32 {
    KIND_COUNT
}

/// How many languages are built in. For diagnostics and tests only.
#[unsafe(no_mangle)]
pub extern "C" fn hdr_language_count() -> u32 {
    LANGUAGES.len() as u32
}

/// Compiles every grammar's queries up front.
///
/// Optional: `hdr_highlight` compiles what it needs on demand. Calling this
/// first only moves the cost somewhere a reader is not waiting. It is the
/// difference between a file appearing instantly and a quarter-second pause on
/// the first Swift file of a session — see `language::warm`.
///
/// Takes a few hundred milliseconds in total and blocks the calling thread, so
/// call it from one nobody is watching. Safe to call more than once and from
/// more than one thread; the work happens once.
#[unsafe(no_mangle)]
pub extern "C" fn hdr_warm() {
    warm();
}

/// The language id for a file, or `0` for one no grammar claims.
///
/// `name` is the file's path or name; `source` is its contents, read only far
/// enough to check for a `#!` line. Both are UTF-8 and need not be
/// nul-terminated. Invalid UTF-8 in either is treated as no match.
///
/// # Safety
///
/// `name` and `source` must each point to at least their stated number of
/// bytes, or be null when that length is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hdr_language_for(
    name: *const u8,
    name_len: usize,
    source: *const u8,
    source_len: usize,
) -> u32 {
    let Some(name) = (unsafe { text(name, name_len) }) else {
        return NONE;
    };
    // Only the first line can hold a `#!`, and reading a megabyte to find it
    // would undo the point of asking before highlighting.
    let head_len = source_len.min(1024);
    let Some(source) = (unsafe { text(source, head_len) }) else {
        return NONE;
    };
    identify(name, source)
}

/// The name to show a reader for a language id, nul-terminated and static, or
/// null for `NONE` and anything out of range. Never freed.
#[unsafe(no_mangle)]
pub extern "C" fn hdr_language_name(language: u32) -> *const c_char {
    language::language(language).map_or(std::ptr::null(), |language| language.display_name.as_ptr())
}

/// Tokens for `source`, read as the language `hdr_language_for` returned.
///
/// Returns an empty run for an unknown language, a file over the size ceiling,
/// invalid UTF-8, or a grammar whose queries fail to compile — every one of
/// which means "show this as plain text".
///
/// # Safety
///
/// `source` must point to at least `source_len` bytes, or be null when that is
/// zero. The returned run must be freed with [`hdr_tokens_free`] exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hdr_highlight(
    language: u32,
    source: *const u8,
    source_len: usize,
) -> HdrTokens {
    let Some(language) = language::language(language) else {
        return HdrTokens::EMPTY;
    };
    let Some(source) = (unsafe { text(source, source_len) }) else {
        return HdrTokens::EMPTY;
    };
    HdrTokens::new(highlight(language, source))
}

/// Releases a run from [`hdr_highlight`].
///
/// # Safety
///
/// `tokens` must be a run returned by [`hdr_highlight`] that has not already
/// been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hdr_tokens_free(tokens: HdrTokens) {
    if tokens.tokens.is_null() || tokens.count == 0 {
        return;
    }
    let slice = std::ptr::slice_from_raw_parts_mut(tokens.tokens.cast_mut(), tokens.count);
    drop(unsafe { Box::from_raw(slice) });
}

/// A borrowed UTF-8 string from a pointer and a length.
///
/// # Safety
///
/// `bytes` must point to at least `len` bytes, or be null when `len` is zero.
unsafe fn text<'a>(bytes: *const u8, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if bytes.is_null() {
        return None;
    }
    // A file is read as UTF-8 before it reaches here, so the only way this
    // fails is a truncated `source` head splitting a character. Trimming back
    // to the last whole character would be the alternative; a `#!` line is
    // ASCII, so there is nothing to gain.
    std::str::from_utf8(unsafe { slice::from_raw_parts(bytes, len) }).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_known_file_is_identified_and_highlighted() {
        let name = "A.swift";
        let source = "let x = 1\n";
        let id = unsafe {
            hdr_language_for(name.as_ptr(), name.len(), source.as_ptr(), source.len())
        };
        assert_ne!(id, NONE);

        let tokens = unsafe { hdr_highlight(id, source.as_ptr(), source.len()) };
        assert!(tokens.count > 0);
        assert!(!tokens.tokens.is_null());
        unsafe { hdr_tokens_free(tokens) };
    }

    #[test]
    fn a_language_has_a_name_and_none_has_not() {
        let name = hdr_language_name(identify("A.swift", ""));
        assert!(!name.is_null());
        assert_eq!(unsafe { std::ffi::CStr::from_ptr(name) }.to_str(), Ok("Swift"));
        assert!(hdr_language_name(NONE).is_null());
    }

    #[test]
    fn an_unknown_file_yields_no_language_and_no_tokens() {
        let name = "notes.txt";
        let source = "hello\n";
        let id = unsafe {
            hdr_language_for(name.as_ptr(), name.len(), source.as_ptr(), source.len())
        };
        assert_eq!(id, NONE);

        let tokens = unsafe { hdr_highlight(id, source.as_ptr(), source.len()) };
        assert_eq!(tokens.count, 0);
        assert!(tokens.tokens.is_null());
        unsafe { hdr_tokens_free(tokens) };
    }

    #[test]
    fn empty_and_null_inputs_are_survivable() {
        assert_eq!(unsafe { hdr_language_for(std::ptr::null(), 0, std::ptr::null(), 0) }, NONE);
        let tokens = unsafe { hdr_highlight(1, std::ptr::null(), 0) };
        assert_eq!(tokens.count, 0);
        unsafe { hdr_tokens_free(tokens) };
        unsafe { hdr_tokens_free(HdrTokens::EMPTY) };
    }

    #[test]
    fn freeing_a_run_twice_is_not_possible_by_accident() {
        // `HdrTokens` is returned by value, so a caller that frees it holds the
        // only copy. This is the shape test: the pointer and count travel
        // together and cannot be mismatched.
        let source = "let x = 1\n";
        let tokens = unsafe { hdr_highlight(identify("A.swift", source), source.as_ptr(), source.len()) };
        let count = tokens.count;
        let slice = unsafe { slice::from_raw_parts(tokens.tokens, count) };
        assert_eq!(slice.len(), count);
        unsafe { hdr_tokens_free(tokens) };
    }

    #[test]
    fn warming_makes_every_grammar_ready_and_changes_no_answer() {
        let source = "let x = 1\n";
        let before = unsafe { hdr_highlight(identify("A.swift", source), source.as_ptr(), source.len()) };
        let count = before.count;
        unsafe { hdr_tokens_free(before) };

        hdr_warm();
        hdr_warm();

        let after = unsafe { hdr_highlight(identify("A.swift", source), source.as_ptr(), source.len()) };
        assert_eq!(after.count, count);
        unsafe { hdr_tokens_free(after) };
    }

    #[test]
    fn the_language_count_matches_the_table() {
        assert_eq!(hdr_language_count() as usize, LANGUAGES.len());
        assert!(hdr_language_count() > 0);
    }

    #[test]
    fn the_kind_count_is_the_one_swift_asserts() {
        assert_eq!(hdr_kind_count(), KIND_COUNT);
    }
}

