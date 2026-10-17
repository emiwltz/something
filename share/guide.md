# Building a space for something

*For the coding agent a person asks to build them a space. Read this file whole before writing.*

something is a Mac app that launches coding agents (Claude Code, Codex, OpenCode, pi), reads the ones started
elsewhere, and shows **spaces**: HTML pages the person asked you to write. A dashboard, a chat, a board of who is
waiting, a small game. This chapter is the **contract**, version 1: what a space can rely on. Later chapters add
examples and the steps to try a space.

*Status: something 1.0 is being built. The app opens a space and serves this contract, but it knows no agent yet:
the state lists none and a launch answers `NOT_SUPPORTED` until the drivers arrive in the next versions.*

Rules that hold everywhere:

- **The contract only grows.** Within version 1, keys, functions, rights, words and codes are added, never removed or
  renamed. Ignore keys and words you do not know.
- **Every key is always present.** What is not known is `null`. Show "unknown", never a zero, an empty string or a guess.
- **Inability is said before the call**: `can`, `because`, `granted.limits`, `granted.unavailable`. Read them and hide
  what cannot be done. A call made anyway fails with a named code; nothing falls back silently.
- `detail` objects are specific to one harness and outside this promise. Your space must work without them.

The same contract as data, for tests: `share/contract/` (`state-example.json`, `shape.json`, `codes.json`).

## Where a space lives

- A single file: `~/something/spaces/<name>.html`.
- A folder: `~/something/spaces/<name>/index.html`, with its own scripts, styles and images next to it.
- Its memory: `~/something/data/<name>.json` (see "Memory").

`<name>` is lowercase letters, digits and `-`.

**A space has no network.** It loads only its own files, inline code, `data:` and `blob:` URLs: no CDN, no web font,
no `fetch` to the Internet. Embed a library in the space at an exact version. `eval` and `new Function` are refused,
so pick a library that does not need them (Alpine.js and the full build of Vue do; the runtime build of Vue does not).
A frame inside your page can hold inline content (`srcdoc`), never another file of the space, and only your page
reaches `something`.
`localStorage` works but is emptied when the window closes: the memory is the only lasting state.

## The declaration

Put this block in the page (or in the folder's `index.html`):

```html
<script type="application/json" id="something">
{
  "contract": 1,
  "title": "Morning review",
  "description": "What my agents did overnight, and who is waiting.",
  "agents": { "see": "all" },
  "rights": ["state", "send:claude", "launch:codex", "store"],
  "folder": "~/code/shop"
}
</script>
```

A folder space may instead put the same object in `something.json`. If both exist, `something.json` is used (warning
`DECLARATION_TWICE`).

| Key | What it says | When absent |
|---|---|---|
| `contract` | The contract you wrote for: `1`. | Read as `1`, warning `CONTRACT_MISSING` |
| `title` | Shown in Home, the window title and the consent window. | The file or folder name |
| `description` | One sentence, shown in the consent window. | Nothing shown |
| `agents` | `{"see":"all"}`, or `{"folders":["~/code/shop"]}`: agents working in those folders or inside them. | Only the agents this space launched |
| `rights` | What the space asks for (see "Rights"). | No right |
| `folder` | Where the agents this space launches work. | The person picks one when a `launch` right is asked |

Only JSON that does not parse (`DECLARATION_UNREADABLE`) or a `contract` higher than something knows
(`CONTRACT_TOO_NEW`) stops the space from opening. Anything else is a warning and the space opens. The smallest
declaration is `{ "contract": 1 }`.

Folders in `agents` are absolute or start with `~`, and match whole path components: `~/code/shop` covers
`~/code/shop/api` but not `~/code/shopping`. Under a folder scope, an agent whose `folder` is `null` is hidden. The
agents this space launched are always in scope.

## Rights

| Right | Allows |
|---|---|
| `state` | Read the agents in scope. |
| `send` | `send`, `interrupt` and `set` on agents this space can write to; `send:claude` limits it to one kind. |
| `launch` | `launch` and `resume` (which is "continue here"), in the granted folder; `launch:codex` limits it to one kind. |
| `store` | The space's own memory. |

Kinds for a right: `claude`, `codex`, `opencode`, `pi`. `open` needs no right: each link is confirmed by the person.
A right asked twice counts once. An unknown word is ignored (warning `UNKNOWN_RIGHT`). A right something knows but
cannot honour (`launch:omp`, `send:omp`) goes to `granted.unavailable` (warning `RIGHT_UNAVAILABLE`).

At the first opening, a window of the Mac lists what you declared, in plain words; the person allows or refuses each
line. Refusals are remembered, and rights can be revoked at any time. **So never assume a right: read
`something.granted`**, and listen to `"granted"` for changes.

## The state

`something.state()` and every `"change"` callback give the whole object, limited to the space's scope. It is pushed
at most four times a second, only when it changed. A shortened example (the full one is
`share/contract/state-example.json`):

```json
{
  "contract": 1,
  "at": "2026-10-17T09:00:04Z",
  "kinds": {
    "claude": { "launch": true, "installed": true, "tested": "2.1.299", "seen": "2.1.301", "reader": "ok", "note": null },
    "omp": { "launch": false, "installed": true, "tested": "18.8.6", "seen": "18.9.0", "reader": "changed",
             "note": "OMP's session files changed shape; its agents are shown as processes only." }
  },
  "agents": [
    {
      "id": "a1", "kind": "claude", "name": "shop", "origin": "launched", "folder": "/Users/example/code/shop",
      "pid": 50123, "alive": true, "evidence": "child", "state": "waiting", "waiting": "permission",
      "thread": "c0ffee00-0000-4000-8000-000000000001",
      "model": "claude-example-model", "mode": "default", "effort": null,
      "options": {
        "model": [{ "value": "claude-example-model", "label": "Example model" }],
        "mode": [{ "value": "default", "label": "Ask before acting" }, { "value": "plan", "label": "Plan only" }],
        "effort": null
      },
      "queue": [{ "id": "q1", "text": "Then run the tests.", "at": "2026-10-17T09:00:02Z" }],
      "can": { "send": true, "steer": true, "queue": true, "interrupt": true, "model": true, "mode": true, "effort": false, "resume": false },
      "because": { "effort": "Claude Code offers no way to change effort during a session." },
      "error": null, "started": "2026-10-17T08:55:00Z", "updated": "2026-10-17T09:00:03Z", "detail": {}
    }
  ],
  "threads": [
    {
      "id": "c0ffee00-0000-4000-8000-000000000001", "agent": "a1", "title": "shop",
      "started": "2026-10-17T08:55:00Z", "complete": true,
      "turns": [
        {
          "id": "c0ffee00-0000-4000-8000-000000000001#1", "state": "working",
          "started": "2026-10-17T08:59:50Z", "ended": null,
          "items": [
            { "id": "i1", "kind": "message", "author": "person", "text": "Add a dark mode to the cart page.",
              "at": "2026-10-17T08:59:50Z", "truncated": false, "tool": null, "decision": null }
          ]
        }
      ]
    }
  ],
  "requests": [
    { "id": "r1", "agent": "a1", "kind": "permission", "tool": "Bash", "about": "npm test", "at": "2026-10-17T09:00:01Z" }
  ]
}
```

### `kinds`: one entry per harness

`claude`, `codex`, `opencode`, `pi`, `omp`. `launch`: something can launch it. `installed`: its program was found
(or `null`). `tested`: the newest version something was proven on; `seen`: the newest found on this Mac, or `null`.
`reader`: `ok`, `changed` (its files changed shape: its agents show as processes only), `unreadable`, or `none`
(nothing of this kind here). `note`: one sentence for the person when something is off, or `null`.

### Agent

| Key | What it holds |
|---|---|
| `id` | Opaque, stable while the agent is listed. Do not parse it. |
| `kind` | `claude`, `codex`, `opencode`, `pi`, `omp`, or `other` (a known program something cannot read: only its process is seen). Show a kind you do not know as "other agent". |
| `name` | The conversation's title, else the folder's last part, else the program name; or `null`. |
| `origin` | `launched` by something, or started `elsewhere` and only read. |
| `folder`, `pid` | Where it works, its process; each may be `null`. |
| `alive` | `true`: a living process holds the conversation. `false`: proven ended. `null`: nothing proves either. |
| `evidence` | Why `alive` is what it is: `child`, `registry`, `lock`, `open-file`, `claim`, `cwd` (the weakest), `recent-write`, `process`; or `null`. |
| `state` | A state word (below). |
| `waiting` | `permission`, `answer`, `none`, or `null` when no source can say. |
| `thread` | The id of its conversation in `threads`, what `resume` takes; or `null`. |
| `model`, `mode`, `effort` | What the agent last reported, never what was asked; each may be `null`. |
| `options` | `{model, mode, effort}`: each a list of `{value, label}` the agent offers, or `null`. |
| `queue` | `[{id, text, at}]`: messages something holds for the agent's next turn. |
| `can` | `send steer queue interrupt model mode effort resume`: what a call would do now. Always booleans. |
| `because` | For a false entry of `can` worth explaining: one sentence. Show it next to the hidden button. |
| `error` | `{code, message}` or `null`: the agent's last error, in its own words when they are clear. |
| `started`, `updated` | ISO 8601 times, or `null`. `updated` is the last activity seen. |
| `detail` | Harness-specific facts. Not part of the contract. |

### State words

| Word | Means |
|---|---|
| `idle` | Alive, no turn running. |
| `working` | A turn is running. |
| `waiting` | Alive and waiting for the person; `waiting` says for what (`permission` or `answer`). |
| `done` | Ended normally. |
| `error` | The last turn or the process failed; `error` says why. |
| `interrupted` | The last turn was stopped before its end, or the process vanished mid-turn. |
| `unknown` | No source can say. Show "unknown", never "idle". |

`state` is `"waiting"` exactly when `waiting` is `"permission"` or `"answer"`. When nothing proves whether its process
lives (`alive: null`), an agent shows `unknown`, or `working` when an open turn was written in the last two minutes
(`evidence: "recent-write"`); it is never `idle`.

### Threads, turns, items, requests

- **Thread** `{id, agent, title, started, complete, turns}`: an agent's current conversation, its last 10 turns.
  `complete` is false when older turns were left out.
- **Turn** `{id, state, started, ended, items}`: `state` is `working`, `done`, `error`, `interrupted` or `unknown`. Its
  last 50 items.
- **Item** `{id, kind, author, text, at, truncated, tool, decision}`: `kind` is `message`, `thought`, `tool` or
  `subagent`; `author` is `person` or `agent`. `text` holds at most 4,000 characters, counted as a person sees them (an emoji is one, though
  `text.length` may say two); `truncated` says it was cut.
  `tool` is `{name, status}` (`running`, `done`, `failed` or `null`) for a tool item, else `null`. `decision` is
  `{by, outcome}` when the agent's own stream says who decided a permission (`by`: `person`, `hook`, `rule`, `mode`;
  `outcome`: `allowed`, `denied`), else `null`. Today only Claude Code launched by something says it.
- **Request** `{id, agent, kind, tool, about, at}`: a `permission` or a `question` from a launched agent, waiting for
  the person in a window of the Mac. **Your space sees it and can never answer it.** Show that the agent waits, and
  say "answer in the window of something".

What is outside the scope is absent: agents, and their threads and requests. Without the `state` right, `state()`
still answers, with only the agents this space launched. Agents seen elsewhere stay listed while alive, and for 24
hours after their last activity.

### What each kind can do once launched

| kind | send | steer | queue | interrupt | model | mode | effort |
|---|---|---|---|---|---|---|---|
| claude | yes | yes | yes | yes | yes | yes (permission modes) | no |
| codex | yes | yes | yes | yes | yes (next turn) | yes (approval policy) | yes (next turn) |
| opencode | yes | no | yes | yes | yes | yes (agents such as build, plan) | yes |
| pi | yes | yes | yes | yes | yes | no | yes (thinking level) |

An agent seen elsewhere can only be resumed ("continue here"), for `claude` and `codex`, once no other process holds
its conversation. Read `can` rather than this table: it is what holds now.

## The bridge: `something.js`

something injects `something.js` before your scripts: `window.something` is there when they run. Every function
returns a promise. A rejected promise carries an `Error` with `.code` (a code below) and `.message` (one sentence that
says what to do): put the sentence on screen.

| Function | Gives | Right |
|---|---|---|
| `something.contract` | `1` (a property) | none |
| `something.granted` | Granted (below), a property set before your scripts run | none |
| `something.state()` | The state | `state` (without it: only the agents this space launched) |
| `something.on(event, fn)` | `"change"`: `fn(state)`; `"granted"`: `fn(granted)`. Returns a function that unsubscribes. | none |
| `something.send(agent, text, {when})` | `{delivery}`: `started`, `steered`, `queued` or `unconfirmed` | `send` |
| `something.interrupt(agent)` | `{interrupted}`: true, or false if no turn was running. The agent's `queue` is emptied either way. | `send` |
| `something.set(agent, {model, mode, effort})` | `{applied}`: `now` or `next-turn`. At least one key, values from `options`. | `send` |
| `something.launch(kind, {folder, model, mode, effort})` | The new agent's `id`. All optional; `folder` is the granted one or inside it. | `launch` |
| `something.resume(kind, threadId)` | The agent's `id`; it runs in the thread's own folder. | `launch` |
| `something.store.get(path)` | The value at `path`, or `null` | `store` |
| `something.store.set(path, value)` | `null`. A `null` value removes the key. | `store` |
| `something.open(url)` | true if the person opened the link, false if they cancelled. `https:`, `http:` or `mailto:`. | none |

`on` with another event throws `UNKNOWN_EVENT` at once.

A link the person clicks (`<a href="https://…">`, `http:` or `mailto:`) opens the same confirmation window by itself.
Call `something.open` for a link your code opens, not from the click handler of such a link: that would ask twice.

**`when` in `send`:**

- `"next"` (the default): after the current turn ends. something holds the message itself (it shows in `queue`) and
  hands it over when the agent finishes its turn.
- `"now"`: into the running turn, at the agent's earliest safe point, without stopping it (steer). Check `can.steer`.
- On an idle agent, both start a turn: `delivery` is `"started"`.
- `"unconfirmed"`: the agent took the message but did not confirm within 10 seconds; the state will show what happened.

A mode that makes an agent ask less (accepting edits by itself, never asking for approval) always opens a confirmation
window of the Mac, whatever the space was granted. A refusal there gives `REFUSED`. A mode that never asks (Claude's
`bypassPermissions`), or one something does not know, is never offered: `VALUE_NOT_OFFERED`, from `set` and `launch`.

```js
const off = something.on("change", (state) => render(state));
const agent = (await something.state()).agents.find((a) => a.can.send);
if (agent) {
  try {
    const { delivery } = await something.send(agent.id, "Then run the tests.", { when: "next" });
    note(`Message ${delivery}.`);
  } catch (error) {
    note(error.message); // one sentence for the person; error.code says which case
  }
}
```

### Granted

```json
{
  "rights": ["state", "send:claude", "store"],
  "refused": ["launch:codex"],
  "unavailable": ["launch:omp"],
  "limits": { "claude": ["effort"], "opencode": ["steer"], "pi": ["mode"] },
  "agents": { "see": "all" },
  "folder": "/Users/example/code/shop"
}
```

`rights`: what the person allowed. `refused`: what they refused. `unavailable`: rights something cannot honour.
`limits`: per kind, what its agents can never do here, so you can hide a button before any agent exists. `agents`: the
scope in force. `folder`: the folder for launches, or `null`.

### Error codes

| Code | When |
|---|---|
| `BAD_PARAMS` | A parameter is missing or of the wrong type. |
| `UNKNOWN_METHOD` | The function is not in this contract. |
| `UNKNOWN_EVENT` | `on` with an event other than `change` or `granted`. |
| `NO_HOST` | The page is not open in something (opened directly in a browser, for example). |
| `RIGHT_NOT_GRANTED` | The right was not declared, was refused, or was revoked. |
| `AGENT_NOT_FOUND` | No such agent in this space's scope. |
| `READ_ONLY_AGENT` | A write to an agent started elsewhere. |
| `NOT_SUPPORTED` | This agent cannot do it: its `can` says false. |
| `VALUE_NOT_OFFERED` | `set` with a value not in `options`, a mode never offered, or the agent replied with a different value. |
| `AGENT_STOPPED` | The agent has ended. |
| `FOLDER_NOT_GRANTED` | `launch` with a folder outside the granted one. |
| `NOT_INSTALLED` | The agent's program was not found on this Mac. |
| `INTERPRETER_NOT_FOUND` | The program was found, but what it needs to run (`node`, for example) was not. |
| `LAUNCH_FAILED` | The program started and stopped at once; the message carries its first error line. |
| `THREAD_NOT_FOUND` | No conversation with this id can be resumed. |
| `STILL_RUNNING` | Another process still holds this conversation; the message says which and what to do. |
| `HELD_ELSEWHERE` | A background service of the agent holds it (Codex); the message names the person's gesture. |
| `REFUSED` | The person said no in a window of the Mac. |
| `BUSY` | A link confirmation is already open for this space. |
| `STORE_FULL` | The memory would exceed 5 MB. |
| `AGENT_ERROR` | The agent refused the request; its words are kept in the message. |

Each code's sentence of what to do is in `share/contract/codes.json`.

## Memory

One JSON object per space, `~/something/data/<name>.json`, through `store`. A path is keys joined by `/`:
`store.get("a/b")` is `doc.a.b` or `null`, and `store.get("")` is the whole document. Writes are whole and atomic.
Limit: 5 MB (`STORE_FULL`).

```js
const seen = (await something.store.get("seen")) ?? [];
await something.store.set("seen", [...seen, "a1"]);
```

## What the person sees of your space

- **The journal.** Every write of your space (`send`, `interrupt`, `set`, `launch`, `resume`, `open`), successful or
  not, adds a line to its journal, shown in its card in Home. It never leaves the Mac.
- **Export.** The person can export your space as one `.something` file (JSON: its files in base64, and its memory
  only if they choose so, and the contract your space declares, so a something that does not know it refuses it). It never carries the rights they gave, the journal, or anything read from an agent, and
  a file of your space that is a link to somewhere else is left out. Keep a space under about 15 MB of files (the
  export, in base64, must stay under 20 MB) and 500 files, and give no file a name starting with ".", or it cannot be
  exported and imported whole. On another Mac, the space asks for its rights again and fills with that Mac's agents.
