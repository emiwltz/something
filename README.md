# something

something is a small local server that links [Herdr](https://github.com/herdrdev/herdr) to an HTML page.

Herdr is the terminal workspace your coding agents run in. something runs next to a Herdr session, detects the agents that live in its panes, its terminals, and serves what they are doing to a page that you build: who is working, who is waiting for you, on which model, with which todos, and what was said. From that page you can also write to an agent. It has no coordinator, no roles, no memories, no imposed interface. It decides nothing: it reads, it serves, and it carries a message when you ask it to.

It is made of a core and extensions. The core knows only Herdr. What an agent writes in its session files (its model, its todos, its conversation) is read by an extension: one file per harness, that you drop in to add it and delete to remove it. A harness is the program that runs an agent: Claude Code, Codex, OpenCode, OMP, pi.

One rule comes before the others: nothing false is shown as true. A piece of data that something cannot read is `null`, and a page writes "unknown".

something is young. No version is tagged yet: its name, the keys of its state and its routes may still change. Where it is going is in the [roadmap](#roadmap).

**Contents:** [Run](#run) · [Plug in a page](#plug-in-a-page) · [The state](#the-state) · [The routes](#the-routes) · [What something knows of each harness](#what-something-knows-of-each-harness) · [Writing an extension](#writing-an-extension) · [How it is made](#how-it-is-made) · [Prove](#prove) · [When it does not work](#when-it-does-not-work) · [Roadmap](#roadmap) · [Security](#security) · [Contributing](#contributing)

## The diagram

```text
 you ◄──► an HTML page (page/)             yours, or the blank page provided
              │  something.js: the page's tools
              ▼
        something (python3 -m something)           127.0.0.1 only, no AI, no dependency
          │ a poll every 2 s
          ├──► the core: Herdr, through its socket    who exists, in what state; carry a message
          └──► the extensions, one per harness        its session files, read, never written: model,
               (extensions/)                          effort, context, tool, question, todos, conversation
```

The core asks Herdr which agents exist and what state they are in. A harness's extension reads its session files and says the rest. something brings the two together in a single object, the state, which it serves to the page. Without any extension, something still works: it shows what Herdr knows.

## Run

With a coding agent, paste this to it:

```text
Set up something for me: read https://raw.githubusercontent.com/emiwltz/something/main/skills/something/SKILL.md and follow it.
```

The agent first says what it is about to do and to install, with the addresses to look at, and asks once whether that suits you. Then it checks Python and Herdr, installs Herdr if it is missing, gets something, starts it, opens the page and says what you are looking at. In an agent that has skills, `skills/something/SKILL.md` can be installed as a skill named `something`.

By hand, to see it first, without Herdr and without any agent:

```sh
git clone https://github.com/emiwltz/something.git
cd something
python3 -m something --example                # http://127.0.0.1:8780/: six made-up agents
```

Open the address in a browser. The blank page lets you choose one of the six agents, read what was said and write to it; a dot marks the two that are waiting for you. Ctrl+C stops something.

With your own agents, start a Herdr session (`herdr`, then your agents in its panes), then, from the repository's folder:

```sh
python3 -m something                          # http://127.0.0.1:8780/
python3 -m something --port 8790              # another port
python3 -m something --once                   # writes the state as JSON on the output, then exits
python3 -m something --example --port 8790    # serves an example state, without Herdr
```

What it needs, and what to expect:

- **Python 3.9 at least, and nothing to install.** No dependency, no build step, no settings file.
- **A running Herdr session** ([how to start one](https://herdr.dev/docs/quick-start/)), except with `--example`. If Herdr is stopped, something says so in `error` and tries again at the next poll.
- **macOS or Linux.** something is developed on macOS, against Herdr 0.9.3, and its tests also run on Linux at each change. On Linux it was tried with a real Herdr session and no agent in it (Ubuntu 24.04, Python 3.12); with agents, Linux has not been tried yet. Windows is not supported: something talks to Herdr through a Unix socket.
- **Its terminal, kept open.** something writes no file: its state lives in memory. What goes wrong is said on the page; the terminal says when Herdr can no longer be read and when it can again, the requests something refused, and a failure of its own. Nothing restarts by itself.

`--once` is also for agents: it is the shortest way to know what is running, without a server.

`--example` is for building a page without running anything else. The state comes from `page/example.json`: six made-up agents that cover the cases (one asks a question, one waits for a permission its log does not name, one has no extension, one is not linked to its session), events, extensions, a snapshot of Herdr. It carries `example: true`, and the blank page says so in plain words. The conversations come from the same file, each returned whole. No message is sent: `POST /api/message` answers 409. With `--once`, the example is written on the output.

## Plug in a page

A file dropped in `page/` is served at the root of the server if it is of one of these types: html, js, css, json, svg, png, jpg, woff2. A hidden file or folder (its name starts with a dot) is not served. A page plugs in with a single tag, then uses the tools of `Something`:

```html
<pre id="agents"></pre>
<script src="/something.js"></script>
<script>
  Something.watch((state) => {
    document.getElementById("agents").textContent = state.agents
      .map((a) => `${a.name ?? a.id} · ${a.state} · ${a.model ?? "unknown"}`)
      .join("\n");
  });
</script>
```

| Tool | What it does |
|---|---|
| `Something.state()` | Returns the present state (a promise). |
| `Something.watch(fn, onLost)` | Calls `fn(state)` right away, then at each change. If the server no longer answers, calls `onLost(sentence)` and resumes by itself. Returns a function that stops the watch. |
| `Something.onEvent(fn)` | Calls `fn(event)` for each new event: an agent is waiting, is done, appears, goes away, or changes state in another way (the kinds are in "The state"). Returns a stop function. |
| `Something.conversation(id, { turns, before })` | Returns `{ agent, turns, older, before }` (a promise): the last turns of an agent's conversation, or those before the cursor `before`. |
| `Something.send(id, text)` | Sends a message to an agent. The promise fails with a readable sentence if the message was not sent. One doubt: when the sentence starts with "Herdr does not answer" or "something does not answer", or says that something answered badly, the message may have left all the same, unless it says "socket missing" or "connection refused". Look at the pane before sending it again. |

Two pages come with something:

- `page/index.html`, the blank page, shows the least: a selector of the agents, with a dot before those that wait for you, the messages of the one you choose, and a field to write to it. Copy it to start yours.
- `page/everything.html`, served at `/everything.html`, shows each key of the state and each tool of `something.js` at work, without design. Take from it what your page needs.

## The state

`GET /api/state` returns a JSON object. Any value that something cannot read is `null`.

```js
{
  generated: "2026-10-07T07:00:00+02:00",        // the time of the poll
  example: false,                                // true only in example mode
  herdr: { connected: true, version: "0.9.3", protocol: 22 },
  error: null,                                   // or a sentence, for instance "Herdr does not answer: …" or "no poll for more than 20 s: …"
  agents: [{
    id: "w2G:p1",                                // the pane's identifier in Herdr, stable
    name: null,                                  // the name given in Herdr, if there is one
    harness: "claude",                           // the name Herdr gives to the agent's program
    state: "working",                            // working, blocked, done, idle, unknown
    since: "2026-10-07T06:58:12+02:00",          // when something saw this state begin; null if it was already there at the first poll that reached Herdr
    title: "something refactoring",                  // the session's title; the terminal's when the log gives none
    cwd: "~/something",
    workspace: "something",                          // the label of the Herdr workspace
    focused: false,                              // the pane has the focus in Herdr
    session: { id: "…", path: "~/.claude/projects/…jsonl" },   // null if something does not link it
    model: "claude-opus-5-5",
    effort: "high",
    context: { tokens: 182000, window: null, percent: null },
    cost: 4.21,                                  // dollars, the harness's estimate
    tool: { name: "Bash", since: "2026-10-07T06:59:40+02:00" },  // the tool in progress, otherwise null
    request: null,                               // what the agent is waiting for from you, see below
    todos: [{ text: "Write the tests", status: "in_progress", phase: null }],
    goal: null,                                  // the background goal (OMP, Codex): { objective, status, tokens, seconds }
    subagents: [{ id: "…", name: "Explore", type: "general-purpose", parent: "w2G:p1",
                  state: "working", model: "sonnet", start: "…", end: null }],
    activity: "2026-10-07T06:59:58+02:00",       // the last write to the log
    read_error: null                             // or the sentence that says why the log was not read
  }],
  events: [{ n: 12, t: "…", kind: "blocked", agent: "w2G:p1", text: "claude is waiting for your answer" }],
  extensions: [{ name: "claude", harness: "claude", error: null }],   // one per extension file
  snapshot: { workspaces: […], tabs: […], panes: […], layouts: […], agents: […] }   // Herdr, as is
}
```

- `null` means two things, and `read_error` tells them apart. If `read_error` holds a sentence, or if `session` is `null`, the log was not read: everything that comes from it is unknown. Otherwise the log was read: `tool`, `request` and `goal` at `null` mean that the reader found none, and any other value at `null` stays unknown. What a log cannot say is in the table "What something knows of each harness": where a permission comes "through Herdr's `blocked` state", a `blocked` agent is waiting for you although `request` is `null`; where a cell says "not read", `null` says nothing. For Codex, `goal` is also `null` when its goals database cannot be read.
- `model` is written the way the harness writes it: `provider/model` when it names the provider, the name alone otherwise.
- `cost` is the harness's estimate, in dollars. OMP, pi and OpenCode keep it up to date at each response. A zero cost is `null` for the three, and so is a cost that four decimals would write as zero: pi and OpenCode count zero for a subscription as for a price they do not know, and OMP counts zero for a response that failed or was cut short. Claude Code only writes it when a session stops or resumes: for a live session, it is the total at that moment, and `null` if it was never stopped. Codex writes no cost.
- `state` is Herdr's own word: `working`, `blocked`, `done` or `idle`. `blocked` means the agent is waiting for you. Anything else is `unknown`, which is never turned into `idle`.
- `request` is `{ kind: "question", questions: [{ question, options, multi }] }` when the agent asks a question, or `{ kind: "permission", tool }` when its log says that it is waiting for a permission; `tool` is `null` when the log does not say for which tool.
- `tool` is the tool in progress, as the session says it. When several are open at once, it is the first one called that has not returned for Claude Code and pi, the last one for the others. For OpenCode, a tool left open in a session silent for two hours is no longer said to be in progress: the response was abandoned. For OMP, a tool left open when OMP stopped is no longer said to be in progress, nor its question to be asked, once OMP has written in the log that it stopped; if OMP was killed before writing it, the tool stays shown until the session receives its next message.
- `todos[].status` is `pending`, `in_progress`, `done` or `blocked`.
- `subagents[].state` is `working`, `done`, `failed` or `unknown`. It is deduced from the log: Herdr does not know subagents. Without an end mark, `working` means it wrote less than 2 minutes ago, or less than 15 minutes ago with a tool open; it is not a proof, and beyond that it is `unknown`. Only those that are working or wrote less than two hours ago are listed, fifty at most.
- `context.percent` only exists if the model's window is known. Claude Code writes it nowhere: only the tokens are given.
- `events` keeps the last hundred. `kind` is `appeared`, `gone`, `blocked`, `done` or `state`. `n` only grows.
- An agent of a harness without an extension is listed with what Herdr says of it; the rest is `null`.
- `extensions` reports each file of `extensions/` whose name does not start with `_` or with a dot. `error` at `null`: the extension is loaded. Otherwise the sentence says why it is not, and the rest works without it.
- `snapshot` is Herdr's response to `session.snapshot`, served as is: its workspaces, its tabs, its panes, their layout, its agents and the focus, under Herdr's keys. It holds what `agents` does not say, like terminals without an agent, and what a more recent Herdr will add. It is `null` whenever `error` holds a sentence: Herdr was not reached, or it answered something that could not be used ("poll failed"). `agents` remains the list to read first: the same agents, completed by the extensions.
- `example` is `true` only in example mode: nothing the state then holds is real.

## The routes

The server listens on `127.0.0.1` only. It refuses a request that is not addressed to it (`127.0.0.1` or `localhost`, with its port), and one that declares another origin than that address. Its answers forbid any other site to show them in a frame.

| Route | Role |
|---|---|
| `GET /` and the files of `page/` | the page |
| `GET /api/state` | the present state |
| `GET /api/stream` | the same state, pushed at each change (`text/event-stream`, event `state`) |
| `GET /api/conversation?agent=‹id›&turns=‹n›&before=‹cursor›` | `{ agent, turns: [{ id, t, from, text, replies: [{ t, text }], tools: [{ name, target }], end }], older, before }`; 20 turns by default, 50 at most; `from` is `user` or `system`; `target` can be `null`; on a very big log, a reader may not go back beyond the last 16 MB |
| `POST /api/message` | `{ agent, text }` → `{ ok: true }`; the message goes to the pane through Herdr |

An error always has the shape `{ "error": "a sentence" }`. Codes: 400 invalid request, 403 host or origin refused or `X-Something` header missing, 404 unknown agent, file or cursor, or an agent without a conversation, 405 method not allowed, 409 the agent is waiting for an answer (Herdr refuses to write over a question) or something is serving the example, 413 body too big, 500 internal server error, 502 Herdr does not answer or refuses the message, or the log cannot be read.

`POST /api/message` requires the `X-Something: 1` header and a JSON body of 16 KB at most; the text is 4,000 characters at most, once the spaces at both ends are removed, without control characters other than the line break and the tab. `something.js` sets the header for you.

## What something knows of each harness

| | OMP | Claude Code | pi | Codex | OpenCode |
|---|---|---|---|---|---|
| Linking the pane to its session | Herdr gives the log's path | Herdr gives the pane's process number; without an answer from Herdr, the folder then the title | Herdr gives the log's path | Herdr gives the identifier, Codex's index gives the log | Herdr gives the identifier, looked up in the database |
| Model | yes | yes | yes | yes | yes |
| Effort | yes | yes | yes | yes | partly: missing for some models |
| Context | tokens; percentage if OMP knows the model | tokens only | tokens; percentage if pi knows the model | tokens; percentage if Codex gives the window | tokens; percentage if OpenCode knows the model |
| Cost | estimated; a zero cost is unknown | at the session's last stop | estimated; a zero cost is unknown | no: Codex writes none | estimated; a zero cost is unknown |
| Tool in progress | yes | yes | yes | yes | yes |
| Question asked | yes | yes | does not exist | partly | yes |
| Permission awaited | through Herdr's `blocked` state | yes, through the registry | does not exist | through Herdr's `blocked` state | through Herdr's `blocked` state |
| Todos | yes, by phases | yes, the tasks | does not exist | yes, the plan | yes |
| Goal | yes | not read | does not exist | yes, the one of `/goal` | does not exist |
| Subagents | yes | yes, agents and workflows | does not exist | yes, the child threads | yes, the child sessions |
| Conversation | yes | yes | yes, the current branch | yes, without the messages between agents; empty if Codex did not write the user's messages | yes |

The readers were last checked against real sessions on 12 October 2026, on a machine with Claude Code 2.1.296, Codex 0.161.0, OMP 18.8.6, OpenCode 2.0.20 and pi 1.0.0: live through Herdr for Claude Code, on the files of the most recent session for the others. A harness changes its files without notice: with a newer version, a reader may read less.

Receiving a message depends on no extension: the core writes to any agent that Herdr knows. An agent of another harness (Gemini, Amp…) therefore shows up too, with what Herdr says of it, and can receive a message.

Answering an agent's question from the page does not exist yet: it has to be done in its pane.

## Writing an extension

An extension is a file `extensions/‹name›.py`: a reader, which knows how to read a harness's sessions. At startup, something loads each file of the folder whose name does not start with `_` or with a dot. The file declares, through agreed names:

```python
HARNESS = "omp"                # the value of Herdr's `agent` field for this harness
HERDR = {"pane.process_info"}  # optional: the reads of Herdr it needs, on top of the snapshot

def session(agent):
    """`agent`: what Herdr says of the pane, an item of `snapshot.agents`. Returns {"id": str, "path": str},
    the absolute path of the file that holds the session, or None if the pane does not safely link to a session."""

def read(session, now):
    """Everything the session says, in the common vocabulary. All the keys are present; an unknown value is None.
    Does not raise for unexpected content; may raise OSError if the source is gone."""

def turns(session, limit=20, before=None):      # optional: without it, this harness has no conversation
    """{"turns": [...], "older": bool, "before": cursor or None}. LookupError if `before` is unknown."""
```

At each poll, for each agent of the harness, the core calls `session`, then `read` with what `session` returned and the time of the poll (`now`, in Unix seconds). It stores in the agent what `read` returns. If `session` or `read` raises, the sentence goes into `read_error` and nothing is made up. `turns` answers `/api/conversation`: the server calls it from its threads, while the loop calls `read`. A module state that both share is protected by a lock.

The common vocabulary is the keys that `read` returns:

| Key | Shape |
|---|---|
| `title` | `str` or `None`: the session's title |
| `model` | `str`: written the way the harness writes it |
| `effort` | `str`: the thinking level |
| `context` | `{"tokens": int, "window": int \| None, "percent": int \| None}`, or `None` if the tokens are unknown; `percent` from 0 to 100 |
| `cost` | dollars (`float`), the harness's estimate; `None` if unknown; a doubtful zero cost is `None` |
| `tool` | `{"name": str, "since": iso \| None}`: the tool in progress, otherwise `None` |
| `request` | `{"kind": "question", "questions": [{"question": str, "options": [str], "multi": bool}]}`, or `{"kind": "permission", "tool": str \| None}`, or `None` |
| `todos` | `[{"text": str, "status": "pending" \| "in_progress" \| "done" \| "blocked", "phase": str \| None}]`; `[]`: read, none; `None`: unknown |
| `goal` | `{"objective": str, "status": "active" \| "paused", "tokens": int \| None, "seconds": int \| None}`, or `None` |
| `subagents` | `[{"id", "name", "type", "parent", "state", "model", "start", "end"}]`; `state` is `working`, `done`, `failed` or `unknown`; `parent`: the `id` of the parent subagent, or `None` for a direct child (the core then puts the pane's identifier there); `start` and `end` in ISO or `None`; only those that are working or wrote less than 2 h ago, 50 at most, sorted by start; `[]`: read, none; `None`: unknown |
| `activity` | iso: the last write to the session |

A key that the session cannot give is `None`: that is normal, and the table "What something knows of each harness" says what is missing. The turns have the shape of the `/api/conversation` route, from the oldest to the most recent; the texts are clipped (message 4,000 characters, reply 8,000, target 160), the reasoning is not returned, and `before` is the identifier of the oldest turn returned if older ones exist, otherwise `None`.

The rules:

- **Nothing false.** An unreadable value is `None`: never 0, never an empty string, never a made-up state. Each field goes through a type guard (`guards.as_dict`, `as_list`, `text`, `number`). An ambiguous link links nothing: `session` returns `None` rather than guessing.
- **Read, and nothing else.** Standard library only. No file writing, no subprocess, no network. The readers' toolbox, `extensions/_reading.py`, helps: `reading.page` returns the page of a conversation read from the end of a log, and `reading.database` opens a SQLite database read-only, and leaves no file next to one that was closed cleanly.
- **Alone.** An extension imports the core by its name (`from something import guards` for the guards, and `herdr` if it declares `HERDR`) and the toolbox (`from extensions import _reading as reading`). It imports no other extension.
- **Private.** Sessions are private conversations: no `print` of their content. The texts of a conversation are clipped with `guards.clip`, dates are written with `guards.iso`.
- **Fast.** `read` answers in less than 50 ms when warm and in less than a second when cold, even on the biggest real file; `turns` in less than a second for 20 turns. A file of several tens of MB is never parsed in full at each poll: memoize (`reading.fingerprint`), read the end (`reading.tail_lines`) or follow as it grows (`reading.lines_from`).
- **Small.** Aim for less than 400 lines. The root of the sessions is a module variable, `ROOT`, that the tests replace.

Its test goes in `tests/test_‹name›.py`. It loads the reader with `extensions.import_file(extensions.FOLDER / "‹name›.py")`, points `ROOT` at a temporary folder and builds fake session files there, in the exact shape of real ones, with made-up texts. It covers "never false" first: missing value → `None`, hostile line skipped, missing or ambiguous link → no session.

An extension that does not load stops nothing: the state says so in `extensions`, with the reason (an error on import, `HARNESS`, `session` or `read` missing, a harness that already has its reader, a Herdr method that is not allowed). To remove it, delete its file and its test: nothing else depends on it.

## How it is made

```text
something/            the core: it knows only Herdr, and names no harness
  __main__.py     the options, the example mode, the loop, the server
  herdr.py        Herdr's socket: one request, one response
  poll.py         one poll: Herdr + readers → the state and the events
  server.py       the routes
  extensions.py   load the files of extensions/
  guards.py       the guards: take a value from elsewhere without ever raising, date it, clip it
extensions/       one reader per harness, one file each
  _reading.py     their toolbox: read the end of a log, follow it, open a database without writing anything
page/
  something.js        the page's tools
  index.html      the blank page: choose an agent, read, write
  everything.html every key of the state at work, without design
  example.json    the state and the conversations of the example mode
skills/
  something/SKILL.md  the way in for a coding agent: set something up, show it, use it
tests/            one file per module and per extension
```

something never runs the `herdr` command. It talks to its socket (`HERDR_SOCKET_PATH`, otherwise `~/.config/herdr/herdr.sock`). The core calls only three methods there: `ping` and `session.snapshot` to read, `agent.prompt` to write. An extension can open one more read by declaring it in `HERDR`. Only one is allowed: `pane.process_info`; an extension that declares another is not loaded. Allowing another is a decision, made in `something/herdr.py`. This list bounds what an extension can declare, nothing more: an extension is still Python code that runs inside something, so read it before dropping it in. Session files are read, never written.

## Prove

```sh
python3 -m unittest discover -s tests     # the Python tests
node --test tests/test_something_js.mjs      # the tests of something.js (Node 22)
```

The tests call neither the real Herdr nor any model: they set up a fake socket and fake logs, in the exact shape of real ones. They open their servers on `127.0.0.1`, on a free port that the system gives them, so they run next to a something that is already running. Green tests do not replace a try on your real Herdr session.

`tests/test_publishable.py` fails when a key of a common shape, an e-mail address or a home folder with a real name is about to be published, in a file or in a commit of the current branch that no remote holds yet.

## When it does not work

- **`error` says "Herdr does not answer"** (the terminal says it too): the Herdr session is stopped, or its socket is not where something looks for it: `herdr status` gives its path, to put in `HERDR_SOCKET_PATH` before starting something. something tries again by itself. During the outage, the conversation of an agent already seen stays readable.
- **`error` says "no poll for more than 20 s"**: the loop that polls Herdr is blocked, for instance by an extension that does not return, or it is dead. something then no longer gives any agent as present: `agents` is empty and `snapshot` is `null`, as when Herdr does not answer; `generated` stays the time of the last poll. A page that watches the stream learns it 15 s later at most. Restart something: a dead loop left its trace in its terminal, a blocked loop does not say by what.
- **An agent has everything at `null` and `read_error` holds a sentence**: something could not link the pane to its log, or the log cannot be read. The sentence says why when the reader knows it. "the pane does not safely link to any session" means that the reader found no session it could tie to this pane without guessing: Herdr gives no session for this pane (see the row "Linking the pane to its session"), the session has just started, or its files are not in the harness's usual folder. To find a session, the readers look nowhere else: `~/.claude`, `~/.codex`, `~/.omp/agent`, `~/.pi/agent`, `~/.local/share/opencode`.
- **A Claude Code pane that has just started is not linked**: Claude Code has not yet written its session's record. `read_error` says so, and it sorts itself out.
- **`read_error` says that several panes compete for a session**: two panes that the reader links to the same session, for lack of a way to tell them apart. something links neither.
- **A harness has everything at `null` although its extension exists**: `extensions`, in the state, says whether it is loaded, and if not why.
- **The page stays empty**: look at something's terminal. If it is stopped, restart it.
- **The page stays empty inside another program's frame or preview pane**: something's answers refuse to be shown in a frame by anything but its own pages. Open the address in a browser tab.
- **Python answers "No module named something"**: start it from the repository's folder, the one that holds this README.
- **The page answers "host or origin refused"**: something only answers at the address it prints. Open exactly `http://127.0.0.1:8780/` or `http://localhost:8780/`; through a tunnel or a proxy, keep the same port number.
- **The port does not open**: something says why and stops. A something that is already running may hold it: use that one, or stop it. Or choose another port with `--port`. `lsof -nP -iTCP:8780 -sTCP:LISTEN` on macOS, `ss -ltnp` on Linux, say who holds a port.

## Roadmap

Where something is going, in this order. These are directions, not promises: nothing here has a date, and the three priorities of [AGENTS.md](AGENTS.md) (stable, minimal, clear) decide what gets in. To work on one of them, open an issue first.

**First: the first five minutes.** Someone who arrives should see their agents on a page without reading this whole README.

- A skill to hand to a coding agent: it says what it is about to do, installs Herdr if it is missing, gets something, starts it, opens the page and says what you are looking at. A first one is in `skills/something/`.
- A first page that shows the least: choose an agent, read what was said, write to it. It is `page/index.html`: one HTML file, without dependency or build step, that you copy and build from. No interface is imposed.
- What is left: try both with people who arrive, and remove what stops them.

**Then: more from the page and from the sessions.**

- Answer an agent's question from the page, instead of in its pane.
- Read what is not read yet, like the goal of Claude Code (`/goal`), and follow the settings that move a harness's folders (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `XDG_DATA_HOME`).
- Readers for more harnesses. An extension is one file: see "Writing an extension".

**A first version.**

- A final name: `something` is a working one.
- The contract of this README, frozen at the first tag: from there, the keys of the state, the routes, the tools of `something.js` and what an extension declares only grow.
- A full trial on Linux, in a fresh machine, with agents at work.

**Later: without Herdr.** Today Herdr is required: it says which agents exist and in what state, and it types the messages. Reading the agents of a machine without it is to be looked at after the rest.

Not planned: a coordinator, roles, memories, orchestration. something stays a link between your agents and your page.

## Security

something reads the session files of your agents and can type a message into their panes: give it the trust you give the agents themselves. It listens on `127.0.0.1` only, refuses a request that is not addressed to it or that declares another origin, lets no other site show its pages in a frame, and opens no connection to the outside. That does not stop what runs on the machine itself: any program, and any other user account, that can open a connection to `127.0.0.1` can do what the page does, read the state and the conversations and send a message. Do not run something on a machine you share. An extension is Python code that runs inside something, and a page can send messages to your agents: read what you drop in.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## Contributing

something stays small on purpose. What does not belong in the core is an extension, or a page of your own: open an issue before a large change. A change comes with its test and, when it changes what this README says, with the README. [AGENTS.md](AGENTS.md) holds the working rules, for people as for coding agents.

Sessions are private conversations: never paste their content, a key or a personal path in an issue, a test or a commit. A commit is public with the address of its author: `tests/test_publishable.py` fails on a commit whose author or committer does not use a no-reply address (GitHub gives you one in its e-mail settings).

## License

[MIT](LICENSE).
