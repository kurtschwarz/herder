import { Plugin } from "@opencode/plugin/tui"
import { report, status, type Snapshot } from "./status.ts"

// Tells the terminal what the session on screen is doing, with OSC 7501. Only
// in Herder, unless the `always` option is set: other terminals ignore the
// sequence, but there is no reason to send it to them.
export default Plugin.define({
  id: "herder.osc-7501",
  setup(context) {
    if (process.env.TERM_PROGRAM !== "Herder" && context.options?.always !== true) return

    // The renderer draws on a thread of its own. `writeOut` queues bytes
    // behind its frames; a plain stdout write can land inside one of them.
    // `writeOut` is not public, so a stdout write is the fallback.
    const renderer = context.renderer as unknown as { writeOut?: (text: string) => void }
    const write = (text: string) => {
      if (typeof renderer.writeOut === "function") renderer.writeOut(text)
      else process.stdout.write(text)
    }

    let sent = ""
    const send = (text: string) => {
      if (text === sent) return
      sent = text
      write(text)
    }

    const finished = new Map<string, NonNullable<Snapshot["finished"]>>()

    const shown = () => {
      const route = context.ui.router.current()
      return route.type === "session" ? context.data.session.root(route.sessionID) : undefined
    }

    const update = () => {
      const root = shown()
      if (!root) return send(report({ state: "idle" }))
      const family = context.data.session.family(root)
      send(report(status({
        running: family.some((id) => context.data.session.status(id) === "running"),
        permissions: family.flatMap((id) => context.data.session.permission.list(id) ?? []),
        forms: family.flatMap((id) => context.data.session.form.list(id) ?? []),
        finished: finished.get(root),
      })))
    }

    // Events can arrive before the data they change has been applied, so
    // what they say is read a moment later, once for a burst of them.
    let pending: ReturnType<typeof setTimeout> | undefined
    const schedule = () => {
      pending ??= setTimeout(() => {
        pending = undefined
        update()
      }, 50)
    }

    const stopListening = context.data.listen(({ details: event }) => {
      switch (event.type) {
        case "session.execution.started":
        case "session.execution.interrupted":
          finished.delete(event.data.sessionID)
          break
        case "session.execution.succeeded":
          finished.set(event.data.sessionID, { outcome: "succeeded" })
          break
        case "session.execution.failed":
          finished.set(event.data.sessionID, { outcome: "failed", message: event.data.error?.message })
          break
        case "permission.asked":
        case "permission.replied":
          void context.data.session.permission.sync(event.data.sessionID).then(schedule, schedule)
          break
        case "form.created":
          void context.data.session.form.sync(event.data.form.sessionID).then(schedule, schedule)
          break
        case "form.replied":
        case "form.cancelled":
          void context.data.session.form.sync(event.data.sessionID).then(schedule, schedule)
          break
      }
      schedule()
    })

    // Switching sessions is not an event, so the route is checked as well.
    let synced: string | undefined
    const tick = setInterval(() => {
      const root = shown()
      if (root && root !== synced) {
        synced = root
        for (const id of context.data.session.family(root)) {
          void context.data.session.permission.sync(id).then(schedule, schedule)
          void context.data.session.form.sync(id).then(schedule, schedule)
        }
      }
      update()
    }, 500)
    update()

    return () => {
      stopListening()
      clearInterval(tick)
      if (pending) clearTimeout(pending)
      write(report("clear"))
    }
  },
})
