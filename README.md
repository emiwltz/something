# something

something is a Mac app that sees the coding agents on your Mac (Claude Code, Codex, OpenCode, pi, OMP), only reading
what they write, and drives the ones it launches itself. It gives **spaces**, free HTML pages your own agent writes
for you, a bridge to those agents: a board of who is waiting, a chat, a summary of your day, whatever you ask for.

*Status: 1.0 is being built; no version is tagged yet (see [Not done yet](#not-done-yet)).*

## The first five minutes

You need a Mac with macOS 15 or later (see [Where it has run](#where-it-has-run)), [Homebrew](https://brew.sh), and
Apple's Command Line Tools, which Homebrew installs with itself (otherwise: `xcode-select --install`, free). Xcode is
not needed. No version is tagged yet, so Homebrew builds the latest code of `main` on your Mac, which takes a few
minutes:

```sh
brew install --HEAD emiwltz/tap/something
something
```

The full name `emiwltz/tap/something` tells Homebrew that you trust this one formula of this tap. Later,
`brew upgrade --fetch-HEAD something` builds the latest code again.

`something` opens the app, with an icon in the menu bar. At its first start it makes `~/something/spaces` (your
spaces) and `~/something/data` (their memory), copies the `agents` space there, and opens it: the list of your agents,
their state, and who is waiting. A window of the Mac first asks you which rights that space may have.

For a space of your own, ask your coding agent. `something guide` prints where the guide for that agent is, and the
skill next to it. Tell your agent, for example: "Read the guide at that path, then make me a space that shows which
of my agents are waiting." It writes the page with `something new`, tests it with `something check`, and you open it
with `something open <name>`. For your agent to know how to build a space anywhere, add the skill (`skill/SKILL.md`,
next to the guide) to it yourself: something never adds anything to your agents.

Each agent you want something to launch must be installed and signed in as you use it in a terminal: `claude`,
`codex`, `opencode`, `pi`. something uses your own settings and your own account for each.

## What it reads, and never writes

something reads, and never writes, each agent's own files: `~/.claude` or `$CLAUDE_CONFIG_DIR` (Claude Code), `~/.codex`
or `$CODEX_HOME`, with its databases in `$CODEX_SQLITE_HOME` when set (Codex), OpenCode's database (in
`~/.local/share/opencode`, or `$OPENCODE_DB`), `~/.pi` and the folders `$PI_CODING_AGENT_DIR` and
`$PI_CODING_AGENT_SESSION_DIR` name (pi), and `~/.omp` (OMP). It opens them read-only
and takes only what a space is shown: the folder, the state, the last messages, what the agent waits for. Nothing it
reads from an agent goes into an export. It also looks at the list of running processes, to tell an agent that runs
from one that ended.

something writes no hook, no MCP server, no skill and no setting into any agent's configuration. What it writes is its
own: `~/something/` (your spaces and their memory) and `~/Library/Application Support/something/` (your answers to the
rights windows, the journals of what spaces asked agents to do, and plan B's spool, below).

## What it launches, and how

A space with the right to launch an agent starts it through that agent's own official channel, in the folder you
chose, with your own configuration:

- **Claude Code**: `claude -p --input-format stream-json --output-format stream-json --verbose
  --permission-prompt-tool stdio`, the channel Anthropic's SDKs use, without `ANTHROPIC_API_KEY` or
  `ANTHROPIC_AUTH_TOKEN` from your environment, so that it uses the account you signed in with. A Claude Code that
  refuses that option is launched again with a permission hook given in `--settings` for that launch only, which waits
  for the same window (plan B); nothing is written in your Claude settings.
- **Codex**: `codex app-server`, its official JSON-RPC channel, one private server per conversation. something never
  joins the server a Codex in your terminal may share.
- **OpenCode**: `opencode acp`, the Agent Client Protocol. One conversation per program.
- **pi**: `pi --mode rpc`, its official channel.
- **OMP** is read, never launched.

Started from a terminal, something gives the agents that terminal's environment, so they find the programs your
terminal finds (less the variables that only say where the terminal runs, such as `TMUX`); started from Finder, it
asks your login shell for its `PATH`. Closing the window keeps something in the menu bar; quitting it stops the agents
it launched, after asking you.

## Permissions and the windows of the Mac

Every decision is yours, in a window of the Mac that a space cannot draw, imitate or answer:

- **Rights.** At the first opening of a space, a window lists what it declares (see your agents, write to them, launch
  them, keep a memory), each to allow or not, and the folder its agents will work in. Your answers are kept, and
  something asks again only for what the space adds; a space opened by its path, outside `~/something/spaces`, keeps
  them only while its window is open. Home shows each space's rights, each with a switch to revoke it.
- **Permissions.** Each permission an agent something launched asks for opens a panel: "Allow once" or "Deny"
  (Escape denies). There is no "always". A question from an agent opens a panel with its choices. A space sees that the
  agent waits, and can never answer for you.
- **Modes.** A mode that makes an agent ask less (accepting edits by itself) always asks you again, with the agent's
  folder. A mode that never asks (Claude's `bypassPermissions`) and a mode something does not know are refused.
- **Links.** A link you click in a space, or one it opens, shows "Open", "Cancel" or "Block links until reload", one
  at a time.
- **Export.** Exporting a space carries its memory only if you choose "With its data", after seeing its keys and size.

A hook you installed in an agent yourself stays in place, and may decide a permission before something's window opens;
the state says so when the agent's own stream tells it.

## No network for spaces

A space loads only its own files, served at `something://space/`, inline code, `data:` and `blob:`. Every other address
is blocked, four times: a sandboxed frame, a content security policy on every file, a content rule list, and a
navigation policy that cancels every page change outside the space. `window.open` opens nothing. The app itself opens
no port, listens on nothing and sends no telemetry.

One gap is known: when you click with the mouse on a link that opens a new window (`target="_blank"`) inside a closed
shadow root (a part of a page hidden from scripts outside it), WebKit looks up the link's server name and opens one
connection to it before it refuses the window. No request is sent on it, but the server and the name lookup see that
it happened, and the page chooses the name, so a page could put a few words in it. It takes your click on such a
link; every other link you click, and every link a page's own script activates, is stopped before any connection.

## The contract for spaces

What a space can rely on is contract 1, written for the agent that builds spaces in the guide,
[share/guide.md](share/guide.md), which is installed with the app (`something guide` prints its path, `something
guide --print` prints it). It holds:

- **the declaration**: a `<script type="application/json" id="something">` block in the page (or `something.json` in a
  folder space), with `contract`, `title`, `description`, `agents`, `rights`, `folder`;
- **the rights**: `state`, `send`, `launch`, `store`, each limited to one kind with `:claude`, `:codex`, `:opencode`
  or `:pi`;
- **the bridge**, `something.js`, injected into every space: `contract`, `granted`, `state`, `on`, `send`,
  `interrupt`, `set`, `launch`, `resume`, `store.get`, `store.set`, `open`;
- **the state**: `contract`, `at`, `kinds`, `agents`, `threads`, `requests`, where what is not known is `null`, never
  a guess;
- **the codes** of every refusal and of `something check`, each with a sentence that says what to do;
- **the export format**, a `.something` file.

The same contract as data, read by the tests: [share/contract/](share/contract/). Within contract 1, keys, functions,
rights, words and codes are only added, never renamed or removed.

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

Every failure is one sentence that says what to type next. The status is 0 when it worked, 1 when it was refused or
failed, 2 when the words were wrong; `check` has its own: 0 no error, 1 errors, 2 it could not run. `check` loads the
space with the app's own lock and bridge, in a window nobody sees, against the invented state of
`share/contract/state-example.json`, never your agents, and writes a snapshot to `$TMPDIR/something-check/`.

Home (in the menu bar) lists your spaces: Open, New, Export, Import, Make default, Show in Finder, and each space's
card with its rights, its folder and its journal. The four examples (your agents, a chat, today, a small game) are
there read-only, with "Make a copy". One space is open at a time, and its window reloads when one of its files
changes.

## What each agent allows, and why

| | send | steer | queue | interrupt | model | mode | effort |
|---|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | yes | yes | yes | yes |
| Codex | yes | yes | yes | yes | yes | yes | yes |
| OpenCode | yes | no | yes | yes | yes | yes | yes |
| pi | yes | yes | yes | yes | yes | no | yes |

- **OpenCode cannot steer** (take a message during a turn): its channel has no way to. A message waits for the next
  turn. OpenCode launched by something cannot ask a question either.
- **pi has no mode, and never asks permission**, by design: it runs commands and edits files without asking you
  first. The rights window says so when a space asks to launch pi.
- **OMP is only read**: launching it is left for after 1.0.
- **An agent started elsewhere is read-only**: something has no channel into a terminal it did not open. In 1.0, a
  Claude Code or Codex conversation can be continued in something ("continue here") once no other process holds it;
  OpenCode, pi and OMP conversations cannot.

A space reads what holds now in each agent's `can` and `because`, not in this table.

## Where it has run

*The suite has run on macOS 27 on Apple silicon (Swift 6.3, Xcode 26), and only there so far. something requires macOS
15 (the package, the app and the formula say so), the oldest macOS this repository's CI runs on: GitHub runs the suite
at each push on macOS 15 and on the newest macOS its runners offer, and installs the formula there with Homebrew; this
line names them once those runs are green.* Intel Macs are not tested.

## Uninstall

```sh
brew uninstall something
brew untap emiwltz/tap                               # if you installed nothing else from it
rm -rf ~/Library/Application\ Support/something      # your answers to the rights windows, the journals
rm -rf ~/something                                   # your spaces and their memory: keep them if you may come back
```

macOS and WebKit may also have made folders named after the app's identifier; this lists them:
`find ~/Library -maxdepth 2 -name 'io.github.emiwltz.something*'`. something wrote nothing in your agents' folders,
so there is nothing to remove there.

## Building from the clone

```sh
git clone https://github.com/emiwltz/something && cd something
swift run something                         # builds, then runs the app in the terminal's own process (no .app)
swift test                                  # the Swift suite
node --test Tests/something-js.test.mjs     # something.js against the contract's cases
tools/make-app.sh <prefix> <version>        # assembles <prefix>/something.app and signs it ad hoc, as the formula does
```

With the Command Line Tools alone (no Xcode), `swift test` does not find Swift Testing by itself; give it the way:

```sh
T=/Library/Developer/CommandLineTools/Library/Developer
swift test -Xswiftc -F -Xswiftc $T/Frameworks -Xlinker -F -Xlinker $T/Frameworks \
  -Xlinker -rpath -Xlinker $T/Frameworks -Xlinker -rpath -Xlinker $T/usr/lib
```

The Homebrew formula is [packaging/homebrew/something.rb](packaging/homebrew/something.rb); the rules for changing
the code are in [AGENTS.md](AGENTS.md).

```text
share/                     something.js, the template, the four examples, the skill, the guide, the contract as data
Sources/SomethingCore/     contract 1: the state, spaces, declarations, rights, the bridge, memory, journal, export, codes
Sources/SomethingAgents/   the engine, a driver per agent it launches, a reader per agent it reads
Sources/something/         the command and the Mac app: menu bar, Home, the space window, the windows that ask you
packaging/, tools/         the app's Info.plist, the Homebrew formula, make-app.sh
.github/workflows/         the suite and a Homebrew install, run by GitHub at each push
Tests/                     the Swift suites, recorded exchanges with invented text, and the node tests of something.js
```

## Not done yet

- **A tagged version.** Until the first tag, `brew install` needs `--HEAD`.

## Security

something opens no port and listens on nothing; a space cannot reach the Internet, nor draw the windows that ask you.
The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A
space is code your agent wrote: read what you open.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## License

[MIT](LICENSE).
