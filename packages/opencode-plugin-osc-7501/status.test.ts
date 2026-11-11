import assert from "node:assert/strict"
import { test } from "node:test"
import { report, status, type Snapshot } from "./status.ts"

const quiet: Snapshot = { running: false, permissions: [], forms: [] }

function fields(sequence: string): Record<string, string> {
  assert.ok(sequence.startsWith("\x1b]7501;") && sequence.endsWith("\x07"), `not a report: ${JSON.stringify(sequence)}`)
  return Object.fromEntries(sequence.slice(7, -1).split(":").map((pair) => pair.split("=", 2) as [string, string]))
}

const decoded = (value: string) => Buffer.from(value, "base64").toString("utf8")

test("a session that has done nothing is idle", () => {
  assert.deepEqual(status(quiet), { state: "idle" })
})

test("a running session is working", () => {
  assert.deepEqual(status({ ...quiet, running: true }), { state: "working" })
})

test("a permission blocks it, even while it runs, and says what it is for", () => {
  const asking = { action: "edit", resources: ["src/main.ts"] }
  assert.deepEqual(status({ ...quiet, running: true, permissions: [asking] }), {
    state: "blocked",
    kind: "permission",
    message: "edit src/main.ts",
  })
  assert.equal(status({ ...quiet, permissions: [{ ...asking, message: "Edit main?" }] }).message, "Edit main?")
})

test("a form is a question", () => {
  assert.deepEqual(status({ ...quiet, running: true, forms: [{ title: "Which branch?" }] }), {
    state: "blocked",
    kind: "question",
    message: "Which branch?",
  })
})

test("a finished run is done, and a failed one an error", () => {
  assert.deepEqual(status({ ...quiet, finished: { outcome: "succeeded" } }), { state: "done" })
  assert.deepEqual(status({ ...quiet, finished: { outcome: "failed", message: "Rate limited" } }), {
    state: "error",
    message: "Rate limited",
  })
  assert.deepEqual(status({ ...quiet, running: true, finished: { outcome: "failed" } }), { state: "working" })
})

test("a report carries the state, the app and the message in base64", () => {
  const sent = fields(report({ state: "blocked", kind: "permission", message: "Edit main.swift?" }))
  assert.deepEqual(Object.keys(sent), ["state", "kind", "app", "msg"])
  assert.equal(sent.state, "blocked")
  assert.equal(sent.kind, "permission")
  assert.equal(sent.app, "opencode")
  assert.equal(decoded(sent.msg!), "Edit main.swift?")
})

test("only a blocked report has a kind", () => {
  assert.equal(fields(report({ state: "working", kind: "permission" })).kind, undefined)
})

test("a report without a message has no msg", () => {
  assert.deepEqual(fields(report({ state: "idle" })), { state: "idle", app: "opencode" })
})

test("a message is one line, without control characters, and cut to fit", () => {
  const sent = decoded(fields(report({ state: "error", message: "first\nsecond\tthird\u0007" })).msg!)
  assert.equal(sent, "first second third")
  const long = decoded(fields(report({ state: "error", message: "é".repeat(500) })).msg!)
  assert.equal(Array.from(long).length, 200)
  assert.ok(long.endsWith("…"))
})

test("the shown session's title is sent, on one line", () => {
  const sent = fields(report(status({ ...quiet, title: "Fix the\nbuild" })))
  assert.deepEqual(Object.keys(sent), ["state", "app", "title"])
  assert.equal(decoded(sent.title!), "Fix the build")
})

test("a title is cut to 192 bytes and ends in an ellipsis", () => {
  const long = decoded(fields(report(status({ ...quiet, title: "é".repeat(300) }))).title!)
  assert.ok(Buffer.byteLength(long, "utf8") <= 192)
  assert.ok(long.endsWith("…"))
  assert.equal(Array.from(long).length, 95)
  const fits = "a".repeat(192)
  assert.equal(decoded(fields(report(status({ ...quiet, title: fits }))).title!), fits)
})

test("a title opencode has not set is left out", () => {
  for (const title of [undefined, "", "  ", "New session - 2026-11-11T10:20:30.123Z", "Child session - 2026-11-11T10:20:30.123Z"]) {
    assert.equal(fields(report(status({ ...quiet, title }))).title, undefined, String(title))
  }
  assert.ok(fields(report(status({ ...quiet, title: "New session about caching" }))).title)
})

test("the home screen has no title", () => {
  assert.equal(fields(report({ state: "idle" })).title, undefined)
})

test("every value is in the protocol's character set", () => {
  const sent = fields(report({ state: "blocked", kind: "question", message: "Ünïcödé? ✓ 🙂" }))
  for (const value of Object.values(sent)) assert.match(value, /^[A-Za-z0-9_.,+/=-]*$/)
})

test("clearing takes every record", () => {
  assert.equal(report("clear"), "\x1b]7501;state=clear\x07")
})
