// Syntax highlighting for Herder's editor pane.
//
// Hand-written to match `src/lib.rs`. The surface is a handful of functions and one
// struct, so a generator would be more machinery than it saves; the Rust tests
// cover the behaviour and Swift's `SyntaxTokenKind` asserts `hdr_kind_count`.

#ifndef HERDER_SYNTAX_H
#define HERDER_SYNTAX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A span of source to paint, in UTF-16 code units from the start of the file,
/// which is what NSTextStorage indexes in.
///
/// `kind` is a `SyntaxTokenKind` raw value.
typedef struct {
    uint32_t start;
    uint32_t end;
    uint32_t kind;
} HdrToken;

/// An owned run of tokens, ordered and non-overlapping. Release it with
/// `hdr_tokens_free`.
typedef struct {
    const HdrToken *tokens;
    size_t count;
} HdrTokens;

/// No language claims this file. A typed constant rather than a `#define` so
/// Swift imports it as a `UInt32` and it can be compared without a cast.
static const uint32_t HDR_LANGUAGE_NONE = 0;

/// How many `SyntaxTokenKind` cases the Rust side defines.
uint32_t hdr_kind_count(void);

/// How many languages are built in.
uint32_t hdr_language_count(void);

/// Compiles every grammar's queries up front, so the first file opened does not
/// pay for it. Optional, blocking, and takes a few hundred milliseconds: call it
/// from a thread nobody is waiting on. Safe to call repeatedly.
void hdr_warm(void);

/// The language id for a file, or `HDR_LANGUAGE_NONE`.
///
/// `name` is the file's path or name and `source` its contents, both UTF-8 and
/// neither needing a trailing nul. Only the head of `source` is read, to look
/// for a `#!` line.
uint32_t hdr_language_for(const uint8_t *name, size_t name_len,
                          const uint8_t *source, size_t source_len);

/// The name to show a reader for `language` ("Swift"), a static nul-terminated
/// string that is never freed. NULL for `HDR_LANGUAGE_NONE`.
const char *hdr_language_name(uint32_t language);

/// Tokens for `source`, read as `language`. Empty for an unknown language or a
/// file past the size ceiling.
HdrTokens hdr_highlight(uint32_t language, const uint8_t *source, size_t source_len);

/// Releases a run from `hdr_highlight`. Safe to call on an empty run.
void hdr_tokens_free(HdrTokens tokens);

#ifdef __cplusplus
}
#endif

#endif // HERDER_SYNTAX_H
