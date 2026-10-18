---
name: something-space
description: Build or change a space for something, the Mac app that shows HTML pages wired to the coding agents on this Mac. Use when the person asks for a space, a page, a board or a dashboard "in something", or for a page that shows, talks to or launches their agents (Claude Code, Codex, OpenCode, pi).
---

# Building a space for something

A space is one HTML page (or a folder with an `index.html`) in `~/something/spaces/`. something opens it in a window
locked off the network and gives it `something.js`, a bridge to the agents on this Mac. The look and the content are
the person's and yours; the contract is in the guide.

## The five steps

1. **Read the guide whole:** `something guide --print`. It is the contract; this skill does not replace it.
   `something guide` says where it is: the template and the examples (`examples/agents.html`, `chat.html`,
   `today.html`, `game.html`) are next to it.
2. **Start from the template:** `something new <name>` (lowercase letters, digits and `-`; `--folder` for several
   files). Then make it the page the person asked for.
3. **Declare only the rights the page uses**, in its `<script type="application/json" id="something">` block:
   `state` to see agents, `send` to write to them, `launch` to start them, `store` for a memory, each with
   `:claude`, `:codex`, `:opencode` or `:pi` to limit it to one kind. The person allows or refuses each one.
4. **Run `something check <name>` until it says `0 errors, 0 warnings`**, then once with `--refuse <right>` for each
   right you declared. Look at the snapshot it writes after each run. Fix each problem with the sentence it gives.
   Check by name, not by a path elsewhere: a space outside `~/something/spaces` has no memory. The check clicks
   nothing: what a button does is proven by reading it against the guide, and by the person in the app.
5. **Tell the person how to open it:** `something open <name>`, or Open in something's Home. The first opening asks
   them for the rights.

## Traps

- No network: no CDN, no web font, no `fetch` to the Internet. Embed what you need. No `eval`, no `new Function`.
- Read `something.granted` and listen to `"granted"`: a declared right may be refused or revoked.
- `null` means unknown: show "unknown", never zero or "idle". Hide what `can` says false, and show `because`.
- A permission or a question is answered in something's window, never in your page: say so on the page. A message
  sent meanwhile waits in the agent's `queue` until the person has answered there.
- A `change` may arrive while the person types: keep the input outside what you redraw.
- Catch every rejected call and show its `message`; an uncaught one is an error of `check`.
- Show the harness names (Claude Code, Codex, OpenCode, pi), never the program names.
- One space is open at a time. OpenCode cannot steer; pi has no modes; agents started elsewhere are read-only.
- In a sandbox without a window server, `check` reports `NO_WINDOW_SERVER`: ask the person to run it, or run it
  outside the sandbox.
