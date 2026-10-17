# something v2

A Mac app you start with one command in the terminal. It opens a real window, launches your coding agents through their official channels, always shows you their permission requests, and lets your own agent draw the interface you want in that window.

It is young. Today it opens a space (an HTML page) in a window locked off the network, asks you which rights the space may have, and answers it through `something.js`. Its engine is being rewritten: until the drivers arrive, it knows no agent, and a launch answers `NOT_SUPPORTED`. The design file (in French, private) is the reference: https://claude.ai/artifact/GwPKPZoVZRASAzkF4ELbeR

It follows [something](https://github.com/emiwltz/something), which stays frozen as it is.

## Run

Needs a Mac with Apple's command line tools (`xcode-select --install`, free; already there if `git` works). Xcode itself is not needed. Then, for each agent you want to launch, that agent installed and signed in as you use it in a terminal: `claude`, `codex`, `opencode`, `pi`.

```sh
swift run something                      # builds, then opens your default space (or Home) and the menu bar icon
swift run something open morning-review  # opens ~/something/spaces/morning-review.html (or its folder); a path works too
swift test                          # the tests: core, agents, the app's window in WebKit, budgets, publishable scan (with Xcode installed; without it, see below)
```

Nothing is signed with a paid Apple account: what is built on the machine itself is not blocked by macOS.

With the command line tools alone, Swift Testing is installed but `swift test` does not find it by itself; give it the way:

```sh
T=/Library/Developer/CommandLineTools/Library/Developer
swift test -Xswiftc -F -Xswiftc $T/Frameworks -Xlinker -F -Xlinker $T/Frameworks \
  -Xlinker -rpath -Xlinker $T/Frameworks -Xlinker -rpath -Xlinker $T/usr/lib
```

## The command

```text
something                       start something, or bring it to the front
something open <name|path>      open a space: a name in ~/something/spaces, or a space's .html file or folder;
                                or import an export (a .something file) into Home, as a double click does
something new <name> [--folder] make a space from the template (with --folder, <name>/index.html, which can hold more files)
something guide [--print]       where the guide for the coding agent that writes your spaces is; --print prints it
something check <name|path> [--json] [--refuse <right>]... [--state <file>] [--journal]
                                test a space as the app loads it, unseen, against an invented state
something --version
```

Every failure is one sentence that says what to type next. The status is 0 when it worked, 1 when it was refused or failed, 2 when the words were wrong (check has its own: 0 no error, 1 errors, 2 it could not run).

`something check` is for the agent that writes your spaces ([share/guide.md](share/guide.md), "Checking your space"). It loads the space with the same scheme, network lock and `something.js` as the app, in a borderless, transparent window that ignores the mouse: it is on screen, because WebKit paints only there, but never in the Dock nor in front, and the process stays an app macOS keeps in the background for the few seconds the check lasts (15 at most). The page gets the invented state of `share/contract/state-example.json` (or `--state <file>`), never your agents, since the output may leave the Mac with the agent's context; every declared right is granted except those named with `--refuse`; write calls are answered as the engine would answer them and reach no agent, `open` answers false, the memory is a throwaway one and the journal is not written. It reports each problem with its code (`share/contract/codes.json`), the calls with their answers, the console, and a snapshot PNG in `$TMPDIR/something-check/`; `--journal` adds the space's last 100 journal lines. Without a window server (an agent's sandbox has none), only the declaration and the files are checked, and `NO_WINDOW_SERVER` says so. A new space never inherits the answers a deleted space of the same name left.

Installed, something is `something.app` with the command beside it. The command hands what you ask to the app through macOS (LaunchServices), which keeps one copy of the app running: `something` starts it, or brings it to the front, with your terminal's environment, so the agents it launches find the programs and the settings your terminal finds (less the variables that only say where the terminal runs, such as CLAUDECODE or TMUX, which would make an agent think it is nested); `something open` hands it the space, or the export to import. Started from Finder or the Dock, the app is the app. Double-clicking an export (`.something`) imports it in Home. Run from the clone (`swift run`), there is no `.app`, and `something` and `something open` run the app in the terminal's own process.

`tools/make-app.sh <prefix> <version> [<program>]` assembles `<prefix>/something.app` from `packaging/Info.plist`, the program (built with `swift build -c release` when none is given) and `share/`, and signs it ad hoc, without an Apple account. The version is written in the app's Info.plist only, and `something --version` reads it there; run from the clone it says `dev`.

## Spaces

A space is an HTML page your coding agent writes: `~/something/spaces/<name>.html`, or a folder `<name>/index.html` with its own files. The guide written for that agent is [share/guide.md](share/guide.md). Without a space to open, something opens your default space; without one, `agents` while it is your only space; otherwise Home. At its first start it makes `~/something/spaces` and `~/something/data`.

- **No network.** A space loads only its own files, served at `something://space/`, inline code, `data:` and `blob:`. Every other address is blocked, four times: the space runs in a sandboxed frame of something's own page, which lets that frame hold nothing but the space; a content security policy on every file; a content rule list; and a navigation policy that cancels every page change outside the space. `window.open` opens nothing, and a frame inside the space holds inline content (`srcdoc`), never another file of the space.
- **Links ask.** A link you click, or one the space opens with `something.open`, shows a window of the Mac: "Open", "Cancel" or "Block links until reload"; one at a time.
- **Rights ask.** At the first opening, a window of the Mac lists what the space declares (see the agents, write to them, launch them, keep a memory), each to tick or not, and the folder its agents will work in. A folder that is not on this Mac is said, and you can choose another. Your answers for a space in `~/something/spaces` are kept in `~/Library/Application Support/something/app.json`, by its name; afterwards something asks only for what the space adds. A space opened by path keeps your answers only while its window is open, so a file that later lands at the same path gets nothing it did not ask you for. A mode that makes an agent ask less (accepting edits by itself, never asking) always asks you again, with the agent's folder; a mode that never asks (Claude's `bypassPermissions`) and a mode something does not know are refused.
- **Its own storage.** `localStorage` works and is emptied when the window closes; no space reads another's. A space in `~/something/spaces` keeps a memory, `~/something/data/<name>.json`, and a journal of what it asked agents to do, next to the grants.
- **Live.** The window reloads when a file of the space changes, and asks again if its declaration asks for more.

- **Home** lists your spaces: Open, New (asks a name and makes the space from the template, as `something new` does), Export, Import, Make default (the one opened at start), Show in Finder. A space you delete or rename in Finder loses your answers for its old name the next time Home or the app looks, so a new space with that name asks again. Examples, when something ships some, sit in their own read-only section with "Make a copy". Beside the list, the selected space's card: its rights with a switch each (switching one off reaches the open space at once, as a `granted` event), "Ask again" (forgets your answers and asks everything again), where it lives and where its agents work, the last 100 lines of its journal, and the readers' notes.
- **Export and import.** Export saves the selected space as one `<name>.something` file: JSON holding its files in base64 and, only if you choose "With its data" after seeing its memory's keys and size, its memory ("Without data" is the default). It never carries your answers, its journal, or a link: a file of the space that is a link to somewhere else is left out, and Export names it; a space, an index.html or a memory that is a link is not exported at all. Import refuses a file that is not an export of something, one made for a newer version of something, a path that is not a plain path inside the space (absolute, `..`, empty or hidden), and a file over 20 MB (base64 makes files a third heavier: about 15 MB of files) or over 500 files, and writes nothing then. A name already taken (by a space, or by a memory left behind) becomes `<name>-2`. The imported space has no rights: it asks at its first opening.
- **One space at a time.** Opening another space closes the open one.
- **Permissions and questions.** Each request of an agent something launched opens a panel of the Mac, one at a time in the order they came: "Allow once" or "Deny" (Escape denies), or the agent's question with its choices. The panels do not block the rest of the app, and a request the agent withdraws closes its panel.

Closing the window keeps something in the menu bar (Home, the open space, Quit); quitting stops the agents it launched, after asking.

## Agents

something launches each agent over its own channel, as follows. Every permission an agent asks waits for your click in a window of the Mac, "Allow once" or "Deny": a space sees that the agent waits, and can never answer for you. Seeing the agents you started elsewhere is not there yet: for now something shows the agents it launched.

Claude Code is launched as `claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio`, the channel Anthropic's SDKs use (the last option is what the SDKs pass to receive permission requests; Claude's help does not list it). It runs with your own Claude Code settings, in the folder you chose, without `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` from your environment, so that it uses the account you signed in with. A Claude Code that refuses that option is launched again with a permission hook given in `--settings` for that launch only, which runs `something hook permission` and waits for the same window (plan B); nothing is written in your Claude settings.

Codex is launched as `codex app-server`, its official JSON-RPC channel, one private server per conversation, with your own Codex configuration. something never joins the server a Codex in your terminal may share.

OpenCode is launched as `opencode acp`: it speaks ACP, the Agent Client Protocol, which other agents speak too. One conversation per program, with your own OpenCode configuration.

pi is launched as `pi --mode rpc`, its official channel, with your own pi configuration. pi never asks permission, by design: there is nothing to show. When a space asks for the right to launch pi, the rights window says that pi runs commands and edits files without asking you first.

## How it is made

```text
share/                     something.js (contract 1's bridge, injected into every space), template.html (the start of a new space), guide.md (the guide for the agent that writes spaces: contract 1), contract/ (the same contract as data, read by the tests)
Sources/SomethingCore/     contract 1: the state (Contract, StateMap, Events), spaces, declarations, rights, the bridge, memory and journal, codes. Foundation only, so it can build on Linux and Windows; it names no agent beyond the kinds a right may name
Sources/SomethingAgents/   the engine (Engine: the seam the app uses; Spawn launches a program, Programs finds it), one driver per agent (ClaudeDriver, CodexDriver, ACPDriver for OpenCode, PiDriver), Claude's plan B (PermissionSpool) and `something try` (DeveloperTrial)
packaging/, tools/         the app's Info.plist and make-app.sh, which assembles and signs something.app
Sources/something/         the command (start, open, new, guide, check, and the routes to hook and try) and the Mac app: menu bar, Home and the space card, the start, the space window (something:// scheme, network lock, reload), its bridge host, native windows and the permission and question panels; carries, asks, decides nothing
Tests/                     SomethingCoreTests (with the budgets and the publishable scan), SomethingAgentsTests, somethingTests (the command's words and statuses; make-app.sh into a temporary folder, run through a wrapper like Homebrew's, its signature verified; the space window in a WebKit view that is never shown: network lock, isolation, scheme, rights; Home, the card and its revocations, the start, the panels), and something-js.test.mjs (something.js on node's own test runner: `node --test Tests/something-js.test.mjs`)
```

A space talks to something with one protocol: it sends `{"contract": 1, "id": ..., "method": ..., "params": ...}` and gets `{"id": ..., "result": ...}` or `{"id": ..., "error": {"code": ..., "message": ...}}`. What is not known is `null`, never missing and never a guess. Another machine would need only a new shell around the same core and the same pages.

This repository is local and private: it has no remote.

## Security

something opens no port and listens on nothing: the window and the agents talk inside the app. A space cannot reach the Internet, and cannot draw the windows that ask you: every right it has, every link it opens, every mode that makes an agent ask less, and every permission an agent asks, waits for your click. One gap is known: when you click with the mouse on a link that opens a new window (`target="_blank"`) inside a closed shadow root (a part of a page hidden from scripts outside it), WebKit looks up the link's server name and opens one connection to it before it refuses the window. No request is sent on it, but the server, and the name lookup, see that it happened, and the page chooses the name, so a page could put a few words in it. It takes your click on such a link; every other link you click, and every link the page's own script activates, is stopped before any connection. The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A page is code your agent wrote: read what you open.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## License

[MIT](LICENSE).
