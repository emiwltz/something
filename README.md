# something v2

A Mac app you start with one command in the terminal. It opens a real window, launches your coding agents through their official channels, always shows you their permission requests, and lets your own agent draw the interface you want in that window.

It is young. Today it opens a space (an HTML page) in a window locked off the network, asks you which rights the space may have, and answers it through `something.js`. Its engine is being rewritten: until the drivers arrive, it knows no agent, and a launch answers `NOT_SUPPORTED`. The design file (in French, private) is the reference: https://claude.ai/artifact/GwPKPZoVZRASAzkF4ELbeR

It follows [something](https://github.com/emiwltz/something), which stays frozen as it is.

## Run

Needs a Mac with Apple's command line tools (`xcode-select --install`, free; already there if `git` works). Xcode itself is not needed. Then, for each agent you want to launch, that agent installed and signed in as you use it in a terminal: `claude`, `codex`, `opencode`, `pi`.

```sh
swift run something                 # builds, then opens the template space and the menu bar icon
swift run something morning-review  # opens ~/something/spaces/morning-review.html (or its folder); a path works too
swift test                          # the tests: core, agents, the app's window in WebKit, budgets, publishable scan (with Xcode installed; without it, see below)
```

Nothing is signed with a paid Apple account: what is built on the machine itself is not blocked by macOS.

With the command line tools alone, Swift Testing is installed but `swift test` does not find it by itself; give it the way:

```sh
T=/Library/Developer/CommandLineTools/Library/Developer
swift test -Xswiftc -F -Xswiftc $T/Frameworks -Xlinker -F -Xlinker $T/Frameworks \
  -Xlinker -rpath -Xlinker $T/Frameworks -Xlinker -rpath -Xlinker $T/usr/lib
```

## Spaces

A space is an HTML page your coding agent writes: `~/something/spaces/<name>.html`, or a folder `<name>/index.html` with its own files. The guide written for that agent is [share/guide.md](share/guide.md). Without a space named on the command line, the window shows `share/template.html`, a plain chat.

- **No network.** A space loads only its own files, served at `something://space/`, inline code, `data:` and `blob:`. Every other address is blocked, three times: a content security policy on every file, a content rule list, and a navigation policy that cancels every page change outside the space. `window.open` opens nothing.
- **Links ask.** A link you click, or one the space opens with `something.open`, shows a window of the Mac: "Open", "Cancel" or "Block links until reload"; one at a time.
- **Rights ask.** At the first opening, a window of the Mac lists what the space declares (see the agents, write to them, launch them, keep a memory), each to tick or not, and the folder its agents will work in. A folder that is not on this Mac is said, and you can choose another. Your answers for a space in `~/something/spaces` are kept in `~/Library/Application Support/something/app.json`, by its name; afterwards something asks only for what the space adds. A space opened by path keeps your answers only while its window is open, so a file that later lands at the same path gets nothing it did not ask you for. A mode that makes an agent ask less (accepting edits by itself, never asking) always asks you again, with the agent's folder; a mode that never asks (Claude's `bypassPermissions`) and a mode something does not know are refused.
- **Its own storage.** `localStorage` works and is emptied when the window closes; no space reads another's. A space in `~/something/spaces` keeps a memory, `~/something/data/<name>.json`, and a journal of what it asked agents to do, next to the grants.
- **Live.** The window reloads when a file of the space changes, and asks again if its declaration asks for more.

Closing the window keeps something in the menu bar; quitting stops the agents it launched, after asking.

## Agents (being rewritten)

What follows is how the previous drivers launched each agent; the new engine (slices 10 to 18) keeps these channels. Every permission an agent asks will wait for your click in a window of the Mac, "Allow once" or "Deny": a space sees that the agent waits, and can never answer for you.

Claude Code is launched as `claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio`, the channel Anthropic's SDKs use (the last option is what the SDKs pass to receive permission requests; Claude's help does not list it). It runs with your own Claude Code settings, in the folder you chose, without `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` from your environment, so that it uses the account you signed in with.

Codex is launched as `codex app-server`, its official JSON-RPC channel, one private server per conversation, with your own Codex configuration. something never joins the server a Codex in your terminal may share.

OpenCode is launched as `opencode acp`: it speaks ACP, the Agent Client Protocol, which other agents speak too. One conversation per program, with your own OpenCode configuration.

pi is launched as `pi --mode rpc`, its official channel, with your own pi configuration. pi never asks permission, by design: there is nothing to show.

## How it is made

```text
share/                     something.js (contract 1's bridge, injected into every space), template.html (the space shown by default), guide.md (the guide for the agent that writes spaces: contract 1), contract/ (the same contract as data, read by the tests)
Sources/SomethingCore/     contract 1: the state (Contract, StateMap, Events), spaces, declarations, rights, the bridge, memory and journal, codes. Foundation only, so it can build on Linux and Windows; it names no agent beyond the kinds a right may name
Sources/SomethingAgents/   one driver per agent (AgentProcess, Claude, Codex, ACP, Pi) and V1's state they still fill
Sources/something/         the Mac app: menu bar, the space window (something:// scheme, network lock, reload), its bridge host, native windows; carries, asks, decides nothing
Tests/                     SomethingCoreTests (with the budgets and the publishable scan), SomethingAgentsTests, somethingTests (the space window in a WebKit view that is never shown: network lock, isolation, scheme, rights), and something-js.test.mjs (something.js on node's own test runner: `node --test Tests/something-js.test.mjs`)
```

A space talks to something with one protocol: it sends `{"contract": 1, "id": ..., "method": ..., "params": ...}` and gets `{"id": ..., "result": ...}` or `{"id": ..., "error": {"code": ..., "message": ...}}`. What is not known is `null`, never missing and never a guess. Another machine would need only a new shell around the same core and the same pages.

This repository is local and private: it has no remote.

## Security

something opens no port and listens on nothing: the window and the agents talk inside the app. A space cannot reach the Internet, and cannot draw the windows that ask you: every right it has, every link it opens, every mode that makes an agent ask less, and every permission an agent asks, waits for your click. One gap is known: when you click with the mouse on a link inside a closed shadow root (a part of a page hidden from scripts outside it), WebKit looks up the link's server name and opens one connection to it before something cancels the visit. No request is sent on it, but the server, and the name lookup, see that it happened, and the page chooses the name, so a page could put a few words in it. It takes your click; a link the page's own script activates is stopped. The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A page is code your agent wrote: read what you open.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## License

[MIT](LICENSE).
