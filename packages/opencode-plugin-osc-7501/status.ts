// What a session is doing, and the OSC 7501 report that says so. No opencode
// imports, so the tests can run it without opencode.
//
// The protocol: https://www.superlogical.com/rex/docs/build/program-status

export type State = "idle" | "working" | "done" | "blocked" | "error"
export type Kind = "permission" | "question" | "auth"

export interface Status {
  readonly state: State
  readonly kind?: Kind
  readonly message?: string
  /** The shown root session's own title, when it has one. */
  readonly title?: string
}

/** What the shown session and its subagents are doing, read off opencode. */
export interface Snapshot {
  /** Whether any session in the family is running. */
  readonly running: boolean
  readonly permissions: ReadonlyArray<{ readonly action: string; readonly resources: readonly string[]; readonly message?: string }>
  readonly forms: ReadonlyArray<{ readonly title: string }>
  /** How the root session's last run ended, if it has ended since it last started. */
  readonly finished?: { readonly outcome: "succeeded" | "failed"; readonly message?: string }
  /** The shown root session's title, as opencode has it. Absent on the home screen. */
  readonly title?: string
}

/**
 * What opencode calls a session before it has a real title. Copied from
 * opencode's own util package, which a plugin loaded as plain source files
 * cannot import.
 */
const fallbackTitle = /^(New session|Child session) - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/

/** Waiting on the person beats working, which beats how the last run ended. */
export function status(snapshot: Snapshot): Status {
  const title = snapshot.title && !fallbackTitle.test(snapshot.title.trim()) ? snapshot.title : undefined
  return { ...state(snapshot), ...(title ? { title } : {}) }
}

function state(snapshot: Snapshot): Status {
  const permission = snapshot.permissions[0]
  if (permission) {
    const message = permission.message || [permission.action, ...permission.resources].join(" ")
    return { state: "blocked", kind: "permission", message }
  }
  const form = snapshot.forms[0]
  if (form) return { state: "blocked", kind: "question", message: form.title }
  if (snapshot.running) return { state: "working" }
  if (snapshot.finished?.outcome === "failed") return { state: "error", message: snapshot.finished.message }
  if (snapshot.finished?.outcome === "succeeded") return { state: "done" }
  return { state: "idle" }
}

const app = "opencode"

/** The longest message sent, in characters. The spec allows 2048 bytes. */
const messageLimit = 200

/** The most bytes of title sent, once decoded. The protocol's limit. */
const titleLimit = 192

/** The whole escape sequence for a status, or for clearing every record. */
export function report(status: Status | "clear"): string {
  if (status === "clear") return "\x1b]7501;state=clear\x07"
  const pairs = [`state=${status.state}`]
  if (status.state === "blocked" && status.kind) pairs.push(`kind=${status.kind}`)
  pairs.push(`app=${app}`)
  const title = status.title ? flatten(status.title, titleLimit) : ""
  if (title) pairs.push(`title=${Buffer.from(title, "utf8").toString("base64")}`)
  const message = status.message ? line(status.message) : ""
  if (message) pairs.push(`msg=${Buffer.from(message, "utf8").toString("base64")}`)
  return `\x1b]7501;${pairs.join(":")}\x07`
}

/** One line with no control characters, which the spec refuses, cut to fit. */
function line(text: string): string {
  const flat = flatten(text)
  const characters = Array.from(flat)
  return characters.length > messageLimit ? characters.slice(0, messageLimit - 1).join("") + "…" : flat
}

/** One line with no control characters, cut to fit `bytes` of UTF-8 if given. */
function flatten(text: string, bytes?: number): string {
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ").replace(/\s+/g, " ").trim()
  if (bytes === undefined || Buffer.byteLength(flat, "utf8") <= bytes) return flat
  const characters = Array.from(flat)
  let size = Buffer.byteLength("…", "utf8")
  const kept: string[] = []
  for (const character of characters) {
    size += Buffer.byteLength(character, "utf8")
    if (size > bytes) break
    kept.push(character)
  }
  return kept.join("").trimEnd() + "…"
}
