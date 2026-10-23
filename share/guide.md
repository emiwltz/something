# Building a space for something

*For the coding agent a person asks to build them a space. Read this file whole before writing.*

something is a Mac app (macOS 15 or later) that sees the coding agents on this Mac (Claude Code, Codex, OpenCode, pi),
launches them, and shows **spaces**: HTML pages that you write for the person. A board of who is waiting, a chat, a
summary of the day, a small game: what they ask for. something gives you an empty page and this contract, version 1. The
look and the content are yours and theirs; the contract only says what a space can rely on.

*This guide is for something 0.2. The state lists the agents something launched and those started elsewhere, and
`resume` continues here a Claude Code or Codex conversation started elsewhere.*

## The five steps

1. **Read this guide.** `something guide` prints where it is; next to it are `template.html`, the templates in
   `templates/` (see "The templates") and the skill in `skill/SKILL.md`.
2. **Start from the closest template**, or from the empty one: `something new <name> --from <template>` copies a
   template to `~/something/spaces/<name>.html`; `something new <name>` writes the empty template there (`--folder`
   makes `<name>/index.html`, for a space of several files). Read the templates for what is possible.
3. **Declare only the rights the page uses** (see "Rights"). The person is asked for each one.
4. **Run `something check <name>` until it reports no error and no warning**, then once more with
   `--refuse <right>` for each right you declared: the page must hide what was refused, not throw.
5. **Tell the person how to open it:** a click on it in something's sidebar, or `something open <name>`. The first
   opening asks them for the rights. Saving the file again reloads the open space.

Rules that hold everywhere:

- **The contract only grows.** Within version 1, keys, functions, rights, words and codes are added, never removed or
  renamed. Ignore keys and words you do not know.
- **Every key is always present.** What is not known is `null`. Show "unknown", never a zero, an empty string or a guess.
- **Inability is said before the call**: `can`, `because`, `granted.limits`, `granted.unavailable`. Read them and hide
  what cannot be done. A call made anyway fails with a named code; nothing falls back silently.
- `detail` objects are specific to one harness and outside this promise. Your space must work without them.
- **Show harnesses by their names**: Claude Code (`claude`), Codex (`codex`), OpenCode (`opencode`), pi (`pi`), OMP
  (`omp`), Antigravity (`antigravity`); a kind you do not know is "other agent".

The same contract as data, for tests: `share/contract/` (`state-example.json`, `shape.json`, `codes.json`).

## The templates

Finished spaces, each one HTML file in `templates/` next to this guide, each passing `something check` with no
problem, with every right it declares and with each one refused. Copy the closest one and change it; the person can
also start from one in something's Templates (File › Templates).

| Template | What it is | Rights |
|---|---|---|
| `agents` (My agents) | Who works, who waits for you, and a word to each. | `state` (all agents), `send` |
| `project` (Project watch) | One folder's progress, and the agents working in it. | `state` (one folder), `send`, `launch`, `store` |
| `brief` (Daily brief) | What your agents did, like a morning paper. | `state` (all agents), `store` |
| `logbook` (Logbook) | Your notes and your agents' days, day by day. | `state` (all agents), `store` |
| `stack` (Stack) | A one-key game for your breaks. | `store` |
| `pet` (Pebble) | A little creature that lives to the rhythm of your agents. | `state` (all agents), `store` |

- `something new <name> --from <template>` copies one; a template is one file, so `--folder` is refused with it.
- Project watch declares the folder `~/code/your-project` in `agents.folders` and `folder`: a placeholder. Write the
  person's project folder in its place in the copy (until then, `check` warns FOLDER_MISSING); something's Use
  Template asks the person for it and does so.
- What they show of the agents is rebuilt from the state each time they open (the threads' last turns), not only
  what happened while they were open; what they keep goes in `store`.

## If you are something's assistant

When something's own window started you, you work in `~/something/spaces` and each message starts with one line from
something, `[something] …`, saying which space is open: "this space" means that one. The folder's `AGENTS.md`, which
something writes there, says how to work in it: read it after this guide. something may lend you `something new`,
`check` and `guide` as tools (`something_new`, `something_check`, `something_guide`): use them when you have them. With
Claude Code, changing the files of that folder and those tools do not ask the person, unless they chose Ask Before
Every Change; anything else asks them. OpenCode asks as the person's own OpenCode settings say. pi never asks:
say so before you run anything outside this folder. A space you make while the person is on the blank page opens by
itself; otherwise something shows it as ready in the sidebar. Never run `something open` after `something new`. No
space can write to you or read what the person tells you.

## Where a space lives

- A single file: `~/something/spaces/<name>.html`.
- A folder: `~/something/spaces/<name>/index.html`, with its own scripts, styles and images next to it.
- Its memory: `~/something/data/<name>.json` (see "Memory").

`<name>` is lowercase letters, digits and `-`. something opens only the spaces of `~/something/spaces`, by name: each
has a memory and a journal. A page elsewhere is copied there first.

**A space has no network.** It loads only its own files, inline code, `data:` and `blob:` URLs: no CDN, no web font,
no `fetch` to the Internet. Embed a library in the space at an exact version. `eval` and `new Function` are refused,
so pick a library that does not need them (Alpine.js and the full build of Vue do; the runtime build of Vue does not).
A frame inside your page can hold inline content (`srcdoc`), never another file of the space, and only your page
reaches `something`. A shadow root your script makes with `attachShadow` is always open (`mode: "closed"` is ignored),
so that something sees the links clicked inside it; one made from HTML (`shadowrootmode`) keeps its mode.
`localStorage` works but is emptied when the space closes: the memory is the only lasting state.

**One space is open at a time.** Opening another closes it. A space cannot open a window, and cannot reach another
space or its memory.

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
| `title` | Shown in the sidebar, the window title and the rights sheet. | The file or folder name |
| `description` | One sentence, shown in the rights sheet and in Info. | Nothing shown |
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

Kinds for a right: `claude`, `codex`, `opencode`, `pi`, `omp`. `open` needs no right: each link is confirmed by the
person. A right asked twice counts once. An unknown word is ignored (warning `UNKNOWN_RIGHT`). A right something knows
but cannot honour (for a kind it only sees: `antigravity` in this version) goes to `granted.unavailable` (warning
`RIGHT_UNAVAILABLE`).

At the first opening, a window of the Mac lists what you declared, in plain words; the person allows or refuses each
line. Refusals are remembered, and rights can be revoked at any time. **So never assume a right: read
`something.granted`**, and listen to `"granted"` for changes.

Ask for the least: a page that only shows agents needs `state` alone; a chat with agents it starts itself needs
`launch` and `send`, and no `state` (it always sees what it launched); a game needs `store`.

## The bridge: `something.js`

something injects `something.js` before your scripts: `window.something` is there when they run. Every function
returns a promise. A rejected promise carries an `Error` with `.code` (see "Every code and its fix") and `.message`
(one sentence that says what to do): put the sentence on screen.

| Function | Gives | Right |
|---|---|---|
| `something.contract` | `1` (a property) | none |
| `something.granted` | Granted (below), a property set before your scripts run | none |
| `something.state()` | The state | `state` (without it: only the agents this space launched) |
| `something.on(event, fn)` | `"change"`: `fn(state)`; `"granted"`: `fn(granted)`. Returns a function that unsubscribes. | none |
| `something.send(agent, text, {when})` | `{delivery}`: `started`, `steered`, `queued` or `unconfirmed` (below) | `send` |
| `something.interrupt(agent)` | `{interrupted}`: true, or false if no turn was running. The agent's `queue` is emptied either way, and a steer the agent has not taken in yet is dropped. | `send` |
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
- On an idle agent, both start a turn.
- On a waiting agent (a `permission` or a `question` in `requests`), a turn is still running: `"next"` is held in
  `queue` and handed over when that turn ends, after the person has answered in something's window; `"now"` steers.
  Neither answers the request. So a reply box on a waiting agent can stay, if it says the message comes after the answer.

What each `delivery` means today:

- `"started"`: the agent had no turn running; the message was written to it and opens a new turn.
- `"steered"`: a turn was running and `when` was `"now"`; the message was written to the agent for that turn (to Codex,
  once the turn's id is known, a moment later). It is not yet proof that the agent took it in: it shows in the thread once
  the agent does. If the agent then refuses it, or the turn fails before it, the agent's `error` says so; an
  interrupt drops it. An agent that cannot steer, or has ended, makes the call fail with its code (`NOT_SUPPORTED`,
  `AGENT_STOPPED`): such a call never answers `"steered"`.
- `"queued"`: a turn was running and `when` was `"next"`; the message is in the agent's `queue`.
- `"unconfirmed"`: kept in contract 1 for a message the agent took without confirming it within 10 seconds.
  something 0.2 never gives it, since it answers as soon as the message is written; treat it as `"steered"`.

A mode that makes an agent ask less (accepting edits by itself, never asking for approval) always opens a confirmation
window of the Mac, whatever the space was granted. A refusal there gives `REFUSED`. A mode that never asks (Claude's
`bypassPermissions`), or one something does not know, is never offered: `VALUE_NOT_OFFERED`, from `set` and `launch`.
OpenCode is launched with `build` or `plan`; another of its agents is chosen with `set`, once `options.mode` lists it.
A launch something would refuse is refused before any window opens.

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
  "unavailable": [],
  "limits": { "opencode": ["steer"], "pi": ["mode"], "omp": ["steer"] },
  "agents": { "see": "all" },
  "folder": "/Users/example/code/shop"
}
```

`rights`: what the person allowed. `refused`: what they refused. `unavailable`: rights something cannot honour.
`limits`: per kind, what its agents can never do here, so you can hide a button before any agent exists. `agents`: the
scope in force. `folder`: the folder for launches, or `null`. A right counts for a kind when `rights` holds it plainly
(`send`) or for that kind (`send:claude`).

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
    "omp": { "launch": true, "installed": true, "tested": "18.8.6", "seen": "18.9.0", "reader": "changed",
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
        "effort": [{ "value": "low", "label": "Low" }, { "value": "high", "label": "High" }]
      },
      "queue": [{ "id": "q1", "text": "Then run the tests.", "at": "2026-10-17T09:00:02Z" }],
      "can": { "send": true, "steer": true, "queue": true, "interrupt": true, "model": true, "mode": true, "effort": true, "resume": false },
      "because": {},
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

`claude`, `codex`, `opencode`, `pi`, `omp`, and `antigravity`, which something only sees by its process. `launch`:
something can launch it. `installed`: its program was found (or `null`, always for a kind something does not launch). `tested`: the newest version something was proven on; `seen`: the newest version its files on this Mac
name, or `null` (OpenCode's: the version that wrote its newest conversation, or, when none says, the name of its
database's last migration).
`reader`: `ok`, `changed` (its files changed shape: its agents show as processes only), `unreadable` (its files
cannot be read now, or reading them takes too long: what was read last stays a moment, then its agents show as
processes only), or `none` (nothing of this kind here). `note`: one sentence for the person when something is off, or `null`.

### Agent

| Key | What it holds |
|---|---|
| `id` | Opaque, stable while the agent is listed. Do not parse it. |
| `kind` | `claude`, `codex`, `opencode`, `pi`, `omp`, `antigravity`, or `other` (a known program something cannot read: only its process is seen). Show a kind you do not know as "other agent". |
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
  `subagent`; `author` is `person` or `agent`. `text` holds at most 4,000 characters, counted as a person sees them (an
  emoji is one, though `text.length` may say two); `truncated` says it was cut.
  `tool` is `{name, status}` (`running`, `done`, `failed` or `null`) for a tool item, else `null`. `decision` is
  `{by, outcome}` when the agent's own stream says who decided a permission (`by`: `person`, `hook`, `rule`, `mode`;
  `outcome`: `allowed`, `denied`), else `null`. An agent something launched says `person` when the person answered
  something's window; only Claude Code also says when a hook, a rule or its mode decided.
- **Request** `{id, agent, kind, tool, about, at}`: a `permission` or a `question` from a launched agent, waiting for
  the person in a window of the Mac. **Your space sees it and can never answer it.** Show that the agent waits, and
  say "answer in something's window".

What is outside the scope is absent: agents, and their threads and requests. Without the `state` right, `state()`
still answers, with only the agents this space launched. Agents seen elsewhere stay listed while alive, and for 24
hours after their last activity. There is no history beyond the current conversation's last 10 turns.

## What each kind can do, and what it cannot

| kind | send | steer | queue | interrupt | model | mode | effort |
|---|---|---|---|---|---|---|---|
| claude | yes | yes | yes | yes | yes (next turn) | yes (permission modes) | yes (the levels its model lists, next turn) |
| codex | yes | yes | yes | yes | yes (next turn) | yes (approval policy) | yes (next turn) |
| opencode | yes | no | yes | yes | yes | yes (agents such as build, plan) | yes |
| pi | yes | yes | yes | yes | yes | no | yes (thinking level) |
| omp | yes | no | yes | yes | yes | yes (default, plan) | yes (thinking level) |

Read `can` rather than this table: it is what holds now. Why the gaps:

- **OpenCode cannot steer**: its channel takes no message during a turn. Send with `when: "next"`. OpenCode launched by
  something cannot ask a question either: it dismisses its own, and the agent's `error` asks the person to have it
  write the question in its reply.
- **pi has no mode**: pi never asks permission, by design; it runs commands and edits files without asking.
- **OMP cannot steer** either (the same channel as OpenCode's): send with `when: "next"`. OMP asks permission only as
  its own settings say, and by default it asks nothing: it runs commands and edits files without asking.
- **An agent started elsewhere is read-only**: something has no channel into a terminal it did not open. In 0.2 only a
  `claude` or `codex` conversation can be resumed ("continue here"), once no other process holds it: its `can.resume`
  is true, and `because.send` ends with "Continue it here to write to it." The new agent is a launch of this space,
  with the `launch` right for that kind. For `opencode`, `pi` and `omp`, `can.resume` is false and `because.resume`
  says why. A permission or a question of an agent started elsewhere is answered where it runs: it is no `request`.
- **The person's assistant is read-only too**: the agent something's own window talks to is listed as launched, but
  its `can` is all false and `because.send` says why; a write to it answers `READ_ONLY_AGENT`. Its conversation, its
  held messages and its requests are the person's: they are never in a space's state. Its `error` keeps its `code`
  but not its words, and no conversation in the spaces folder is ever listed as seen elsewhere.
- **`other` agents are seen by their process only**: no conversation, no state beyond `unknown`.

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
  not, adds a line to its journal, shown in Info beside the space. It never leaves the Mac.
- **Export.** The person can export your space as one `.something` file (JSON: its files in base64, and its memory
  only if they choose so). The export carries the contract your space declares; a something that does not know that
  contract refuses to import it. It never carries the rights they gave, the journal, or anything read from an agent,
  and a file of your space that is a link to somewhere else is left out. Keep a space under about 15 MB of files (the
  export, in base64, must stay under 20 MB) and 500 files, and give no file a name starting with ".", or it cannot be
  exported and imported whole. On another Mac, the space asks for its rights again and fills with that Mac's agents.
- **The assistant.** The person's assistant floats at the bottom of the window, over the bottom of your space: keep
  what matters out of the last 100 points, or let it scroll. ⌘K, ⌘J, ⌘R and ⌘N belong to something; a space should not
  rely on them. An error your page does not catch shows "This space has an error.", and the person may ask their
  assistant to fix it: something tells the assistant the codes (`SCRIPT_ERROR`, `PROMISE_REJECTED`), never your
  page's words.

## Checking your space

```sh
something check <name|path> [--json] [--refuse <right>]... [--state <file>] [--journal]
```

Run it after each change. It loads your space as the app does (same `something://` address, same network lock, same
`something.js`) in a window nobody sees, and reports what went wrong, each problem with its code, its place and what
to do. Exit status: `0` no error (warnings allowed), `1` errors, `2` the check could not run.

- **An invented state**, `share/contract/state-example.json`: a Claude Code launched by something and waiting on a
  permission, a Codex started elsewhere and done, an `other` agent in `unknown`. To see another case (an idle launched
  agent, no agent at all), copy that file, change values but keep every key, and pass it with `--state`. Never the
  person's agents: what the check prints may leave the Mac with your context. In your declaration, `~`
  stands here for `/Users/example`, the invented state's home, so a scope written with `~` meets its agents.
- **Every right you declare is granted**, except those named with `--refuse`: run once with `--refuse send` (or another
  right) to see that your page reads `something.granted` and hides what was refused instead of throwing. The check
  cannot judge what the page shows: look at the snapshot of that run (each run replaces the last one). Name a right
  as you declared it: a word that names none of them stops the check (status `2`), since nothing would be refused.
- **Nothing is clicked or typed.** Only the calls your page makes by itself are run, while it loads and in the
  half second after the snapshot. A path behind a button (a `send`, its errors) is not run: read it again
  against this guide, and ask the person to try it once in the app.
- **Calls are answered** as the engine would answer them, and reach no agent: a launch returns an id such as
  `check-1` that no state lists, `open` answers `false` (as if the person cancelled), and the memory is a throwaway
  one, empty at the start. Each call is listed with its answer (for `state`, the ids of the agents your page saw).
- **What it reports**: uncaught errors with file, line and column, unhandled rejections, `console.error`, missing files,
  loads and navigations the lock blocked, calls a real engine would reject, rights you use without declaring, a
  declaration that does not read, a page that does not load within 15 seconds or whose process ends. Each run also
  writes a snapshot, a PNG of the page after it painted: look at it. A space of `~/something/spaces` has it in the
  hidden folder `.check/<name>.png` there, which is never a space; a page elsewhere, in `$TMPDIR/something-check/`.
  `--json` gives the same as one JSON object, with the console and the snapshot's path. The page is still heard for
  half a second after the snapshot, so a timer that throws soon after the load is reported too.
  `received` says what state the page was given, and is null when the page was not loaded.
- `--journal` adds the last 100 lines of your space's real journal.
- **In a sandbox without a window server** (where many coding agents run their commands), only the declaration and the
  files are checked, and `NO_WINDOW_SERVER` says so: ask the person to run the check, or run it outside the sandbox.

Check the space by its name, in `~/something/spaces`: a space checked by a path from elsewhere has no memory, and its
`store` calls are refused.

The `--json` shape is `share/contract/check-example.json`.

## Every code and its fix

The same list as data: `share/contract/codes.json`.

### From the bridge (a rejected call)

| Code | When | Fix |
|---|---|---|
| `BAD_PARAMS` | A parameter is missing or of the wrong type. | Pass the parameters the guide lists for this function, with their types. |
| `UNKNOWN_METHOD` | The function is not in this contract. | Use only the functions of something.js listed in the guide. |
| `UNKNOWN_EVENT` | `on` with an event other than `change` or `granted`. | Listen to "change" or "granted". |
| `NO_HOST` | The page is not open in something (opened directly in a browser, for example). | Open the space in something; a browser alone has no agents to give it. |
| `RIGHT_NOT_GRANTED` | The right was not declared, was refused, or was revoked. | Declare the right, and read something.granted to hide what the person did not allow. |
| `AGENT_NOT_FOUND` | No such agent in this space's scope. | Use an id from the latest state; agents come and go. |
| `READ_ONLY_AGENT` | A write to an agent started elsewhere. | Check can before writing; offer resume to continue this conversation here. |
| `NOT_SUPPORTED` | This agent cannot do it: its `can` says false. | Check can and because before the call, and hide what this agent cannot do. |
| `VALUE_NOT_OFFERED` | `set` with a value not in `options`, a mode never offered, or the agent replied with a different value. | Pick a value from the agent's options. |
| `AGENT_STOPPED` | The agent has ended. | Launch or resume an agent to go on. |
| `FOLDER_NOT_GRANTED` | `launch` with a folder outside the granted one. | Launch in something.granted.folder or a folder inside it. |
| `NOT_INSTALLED` | The agent's program was not found on this Mac. | Tell the person to install this agent; kinds says which ones are installed. |
| `INTERPRETER_NOT_FOUND` | The program was found, but what it needs to run (`node`, for example) was not. | Show the message to the person: it names what to install. |
| `LAUNCH_FAILED` | The program started and stopped at once. | Show the message to the person: it carries the agent's first error line. |
| `THREAD_NOT_FOUND` | No conversation with this id can be resumed. | Use a thread id from the latest state. |
| `STILL_RUNNING` | Another process still holds this conversation. | Show the message to the person: it says which process and what to do. |
| `HELD_ELSEWHERE` | A background service of the agent holds it (Codex). | Show the message to the person: it names the gesture that frees it. |
| `REFUSED` | The person said no in a window of the Mac. | Accept the answer; do not ask again in a loop. |
| `BUSY` | A link confirmation is already open for this space. | Wait for the first link's answer before opening another. |
| `STORE_FULL` | The memory would exceed 5 MB. | Store less: remove old values with store.set(path, null). |
| `AGENT_ERROR` | The agent refused the request; its words are kept in the message. | Show the message to the person: it keeps the agent's own words. |

### From `something check`

| Code | Level | Fix |
|---|---|---|
| `SPACE_NOT_FOUND` | fatal | Give the name of a space in ~/something/spaces, or the path of its file or folder. |
| `NO_WINDOW_SERVER` | fatal | Run the check from a logged-in session of the Mac. |
| `STATE_FILE_UNREADABLE` | fatal | Start from share/contract/state-example.json and keep every key. |
| `DECLARATION_UNREADABLE` | error, not displayed | Fix the JSON of the declaration; the space does not open until it parses. |
| `CONTRACT_TOO_NEW` | error, not displayed | Write "contract": 1, or update something. |
| `SCRIPT_ERROR` | error | Fix the code at this line; the page stops running at this error. |
| `PROMISE_REJECTED` | error | Catch the rejection and show its message to the person. |
| `RESOURCE_MISSING` | error | Add the file to the space, or fix the path that names it. |
| `LOAD_FAILED` | error | Check that the space's HTML file exists and is readable. |
| `LOAD_TIMEOUT` | error | Make the page load faster: no endless loop before the first paint. |
| `PAGE_CRASHED` | error | Look for code that uses too much memory or loops without end. |
| `DECLARATION_MISSING` | warning | Add `<script type="application/json" id="something">{"contract": 1}</script>`. |
| `DECLARATION_TWICE` | warning | Keep one declaration: remove the block or something.json. |
| `CONTRACT_MISSING` | warning | Add "contract": 1 to the declaration. |
| `SCOPE_INVALID` | warning | Write "agents": {"see": "all"} or {"folders": ["~/code/example"]}. |
| `UNKNOWN_RIGHT` | warning | Use one of: state, send, launch, store, optionally with :kind. |
| `RIGHT_UNAVAILABLE` | warning | Read something.granted.unavailable and hide what depends on it. |
| `RIGHT_NOT_DECLARED` | warning | Declare the right in rights, or do not call this function. |
| `RIGHT_REFUSED` | warning | Read something.granted and hide what the person refused. |
| `RESOURCE_BLOCKED` | warning | Put the file in the space, or embed the library at an exact version. |
| `NAVIGATION_BLOCKED` | warning | Use something.open(url) for links that leave the space. |
| `BRIDGE_ERROR` | warning | Read the code's own sentence, and check granted and can before the call. |
| `CONSOLE_ERROR` | warning | Show the problem to the person on the page, or fix its cause. |
| `FOLDER_MISSING` | warning | Declare a folder that exists, or leave folder out and let the person choose one. |
| `TOO_HEAVY` | warning | Remove files the space does not use, or make its images smaller. |
| `UNKNOWN_KEY` | info | Remove the key, or check its spelling. |

`BRIDGE_ERROR` carries the bridge code a real engine would also give, with that code's fix.

## Traps

- A `<script src="https://…">`, a web font or a `fetch` to the Internet is blocked: embed what you need.
- A library that needs `eval` or `new Function` does not run.
- `hidden` does not hide an element your CSS gives a `display`: add `[hidden] { display: none !important; }`.
- A right in the declaration is not a right granted: read `something.granted`, and listen to `"granted"`.
- `null` is not zero: show "unknown". A state word or kind you do not know is not an error: show it as unknown, or as
  "other agent".
- A permission or a question is answered in something's window, never in your page.
- A rejected promise left uncaught is an error of `check`: catch each call and show its `message`.
- An `id` from an old state may be gone: take ids from the latest state.
- A `change` may arrive while the person types: keep the input outside what you redraw, or its text and focus are lost.
- Calling `something.open` from the click handler of an `<a href>` asks the person twice.
- The memory is one JSON document: keep it small, and write whole values.
- A space stays open all day: animate only `opacity` and `transform`, never a shadow, a filter or a size, which are
  painted again at every frame; honor `prefers-reduced-motion`.
