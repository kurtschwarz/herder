# Herder

The words this app uses for its own parts. Each is one thing: if the code or a conversation uses another word for it, one of them is wrong.

## Task Manager

**Task Manager**:
The one window, opened from Tools ▸ Task Manager, that lists every process Herder is running and what each is using. It reads the system on a timer for as long as it is open and not at all otherwise.
_Avoid_: Activity Monitor (it is not that app), process list.

**Process group (row)**:
A heading row in the Task Manager's table that holds other rows and shows their subtotals: Agent Sessions, Herder, and under Herder, Terminals and Other. It never moves when rows are sorted. Not an OS process group; a process that Herder starts is under the tab that started it, whatever group the OS puts it in.
_Avoid_: section, category.

**Running process registry**:
The app-wide list of tabs that have a process running, in every window: each agent session and each terminal, with the pid it started, its title, and a way to bring it forward. Windows write it as their processes start and end, and the Task Manager reads it to know which processes belong to which tab. Not the list of agent sessions (that is the sidebar's, and includes ones with no process).
_Avoid_: process table, tab list.
