# Writing a page for something

*For the coding agent a person asks to build them a page. Read this file whole before writing.*

something is a Mac app that launches coding agents (Claude Code, Codex, OpenCode and pi for now) and shows one page in its window. The person decides what that page is: a dashboard, a chat, a small game where the agents talk, a Tamagotchi. You write it.

## Where a page lives

For now the window shows one page, `share/template.html` in something's folder, a plain chat. The person may edit it, or copy their own page over it; spaces of their own, folders where each page lives, come in a later version.

The window reloads by itself each time that file is saved, so you can work and they can watch.

Plain HTML, CSS and JavaScript in that one file. No build step: what you write is what runs.

## Talking to something

Load the tools first, then use `window.something`:

```html
<script src="something://app/something.js"></script>
```

| Tool | What it does |
|---|---|
| `something.state()` | A promise of the whole state (below). |
| `something.subscribe(fn)` | Calls `fn(state)` each time the state changes: a message, a status, a request. |
| `something.launch("claude")` | Asks the person for a folder, then launches Claude Code (or `"codex"`, `"opencode"`, `"pi"`) there. Resolves to the agent's id. |
| `something.send(agentId, text)` | Asks the person first, in a window of the Mac, then sends. Rejects when they refuse. |
| `something.store.get(key)` / `store.set(key, value)` | The page's own memory, kept between launches. JSON values; `null` removes. |

Every promise rejects with an `Error` whose message is one sentence for the person: show it.

## The state

```json
{
  "agents": [
    {
      "id": "claude-1",
      "name": "my-project",
      "harness": "claude",
      "folder": "/Users/example/my-project",
      "status": "waiting",
      "model": "claude-example-1",
      "mode": "default",
      "messages": [
        { "from": "you", "text": "Add a README." },
        { "from": "agent", "text": "I will write README.md." }
      ],
      "request": { "id": "r1", "tool": "Write", "about": "README.md" },
      "error": null
    }
  ]
}
```

- `harness`: `"claude"`, `"codex"`, `"opencode"` or `"pi"`.
- `mode`: the agent's own setting for what it may do without asking: Claude's permission mode (`"default"`, `"acceptEdits"`, `"plan"`…), Codex's approval policy (`"untrusted"`, `"on-request"`, `"never"`, `"granular"`), OpenCode's agent (`"build"`, `"plan"`). pi has no such setting and never asks: its `mode` is always `null`.
- `status`: `"working"`, `"waiting"` (on `request`), `"idle"` or `"stopped"`.
- `request`: the permission the agent waits on, or `null`. The person answers it in a window of the Mac; a page cannot.
- `error`: what went wrong, in one sentence, or `null`.
- **`null` means unknown.** Show "unknown", never a zero or a guess. Every key is always there.

## Rules

- **No network.** A page cannot load anything from the Internet: no CDN, no fonts, no fetch. Write everything in the page itself. What the page shows of the agents stays on the machine.
- **Writing is the person's word.** `send` may be refused; a permission is never answered by a page. Show that an agent waits, and say where to answer.
- **Show failures.** A rejected promise, an `error` in the state: put the sentence on screen.
- **Do not change** `share/something.js`, `share/guide.md` or anything else in something's folder: they belong to something. Only `share/template.html` is the page.
