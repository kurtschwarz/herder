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
}

/** What the shown session and its subagents are doing, read off opencode. */
export interface Snapshot {
  /** Whether any session in the family is running. */
  readonly running: boolean
  readonly permissions: ReadonlyArray<{ readonly action: string; readonly resources: readonly string[]; readonly message?: string }>
  readonly forms: ReadonlyArray<{ readonly title: string }>
  /** How the root session's last run ended, if it has ended since it last started. */
  readonly finished?: { readonly outcome: "succeeded" | "failed"; readonly message?: string }
}

/** Waiting on the person beats working, which beats how the last run ended. */
export function status(snapshot: Snapshot): Status {
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

/** The whole escape sequence for a status, or for clearing every record. */
export function report(status: Status | "clear"): string {
  if (status === "clear") return "\x1b]7501;state=clear\x07"
  const pairs = [`state=${status.state}`]
  if (status.state === "blocked" && status.kind) pairs.push(`kind=${status.kind}`)
  pairs.push(`app=${app}`)
  const message = status.message ? line(status.message) : ""
  if (message) pairs.push(`msg=${Buffer.from(message, "utf8").toString("base64")}`)
  return `\x1b]7501;${pairs.join(":")}\x07`
}

/** One line with no control characters, which the spec refuses, cut to fit. */
function line(text: string): string {
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ").replace(/\s+/g, " ").trim()
  const characters = Array.from(flat)
  return characters.length > messageLimit ? characters.slice(0, messageLimit - 1).join("") + "…" : flat
}
