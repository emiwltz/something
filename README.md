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

`something` opens the app's window: your spaces in the sidebar, the open one in the middle, and Info (⌥⌘I) beside it.
At its first start it makes `~/something/spaces` (your spaces) and `~/something/data` (their memory), and shows a
short tour (again from Help › Welcome Tour): what something is, then which of your coding agents builds your spaces.
It starts no agent. Installed with Homebrew, the tour also offers to add something to `~/Applications`, so that
Spotlight finds it (Spotlight does not look where Homebrew installs apps): a small launcher that opens it. The tour
ends on the blank page (New Space, ⌘N): describe the space you want, or click a suggestion, and your assistant builds
it; it opens by itself when it is ready. At its first opening, a sheet asks you which rights that space may have.

For a space of your own, ask your coding agent. `something guide` prints where the guide for that agent is, and the
skill next to it. Tell your agent, for example: "Read the guide at that path, then make me a space that shows which
of my agents are waiting." It writes the page with `something new`, tests it with `something check`, and it appears
in the sidebar: one click opens it (or `something open <name>`). For your agent to know how to build a space anywhere, add the skill (`skill/SKILL.md`,
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
own: `~/something/` (your spaces, their memory and your assistant's `AGENTS.md` and `CLAUDE.md`) and `~/Library/Application Support/something/` (your answers to the
rights sheets, the window's memory, the journals of what spaces asked agents to do, and plan B's spool, below).

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
asks your login shell for its `PATH`. Closing the window keeps something running, with its agents: its Dock icon or
`something` shows the window again. Quitting stops the agents it launched, after asking you.

## Your assistant

At the bottom of the window, a bar talks to your own coding agent, which builds and changes spaces with you: Claude
Code, OpenCode or pi, the one you choose among those installed (Codex can't build spaces yet: inside its sandbox
`something check` cannot load a page). Nothing starts before your first message; it then works in
`~/something/spaces`, with your account and settings, as in Terminal. Each message starts with one line from
something saying which space is open. After 30 minutes without a turn it is stopped to save memory, and a new
conversation starts each time something starts.

something never answers for you. Your assistant may change your spaces and run something's own commands without
asking; everything else it does asks you, as your agent's own settings decide. For Claude Code that is
`--allowedTools` with edits and writes in `~/something/spaces` and `something new`, `check`, `open` and `guide`; for
OpenCode and pi nothing is added (pi never asks). "Ask Before Every Change", in the bar's agent menu, turns that off
from the next conversation. No space can see what you say to your assistant, or write to it.

To tell it what something is, something writes `AGENTS.md` and `CLAUDE.md` into `~/something/spaces` at each start. A
file whose first line you removed is yours: something leaves it alone.

## Permissions and the windows of the Mac

Every decision is yours, in a window of the Mac that a space cannot draw, imitate or answer:

- **Rights.** At the first opening of a space, a sheet on the window lists what it declares (see your agents, write to
  them, start them, remember things), each to allow or not, and the folder its agents will work in. Your answers are
  kept, and something asks again only for what the space adds. Info (⌥⌘I) shows each right of the open space, with a
  switch to revoke it, and what the space did.
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
shadow root (a part of a page hidden from scripts outside it) written in HTML, in the page or in HTML a script parses,
such as with `setHTMLUnsafe` (one a script makes with the page's own `attachShadow` is opened by something, so its
links are stopped like any other), WebKit looks up the link's server name and opens one connection to it before it
refuses the window. No request is sent on it, but the server and the name lookup see that it happened, and the page
chooses the name, so a page could put a few words in it. It takes your click on such a link; every other link you
click, and every link a page's own script activates, is stopped before any connection.

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
something open <name>           open a space of ~/something/spaces; or import an export (a .something file), as a
                                double click does
something new <name> [--folder] make a space from the template (with --folder, <name>/index.html, which can hold more files)
something new <name> --from <t> make a space from a template: agents, project, brief (one file; no --folder)
something guide [--print]       where the guide for the coding agent that writes your spaces is; --print prints it
something check <name|path> [--json] [--refuse <right>]... [--state <file>] [--journal]
                                test a space as the app loads it, unseen, against an invented state
something --version
```

Every failure is one sentence that says what to type next. The status is 0 when it worked, 1 when it was refused or
failed, 2 when the words were wrong; `check` has its own: 0 no error, 1 errors, 2 it could not run. `check` loads the
space with the app's own lock and bridge, in a window nobody sees, against the invented state of
`share/contract/state-example.json`, never your agents, and writes a snapshot to `$TMPDIR/something-check/`.

The window's sidebar lists your spaces by title; one click opens one, and the window opens on the last one open. A
page of the folder without a declaration is listed as "not a space yet". A space's context menu has Show in Finder,
Export… and Move to Trash… (its memory goes with it); File › Import Space… takes an export. A page elsewhere is not
opened: copy it into `~/something/spaces` first. One space is open at a time, and it reloads when one of its files
changes. Templates (File › Templates, or the sidebar) shows finished spaces to start from: My agents, Project watch
and Daily brief; Use Template makes one of them yours (Project watch first asks which folder it follows), and
`something new <name> --from <template>` does the same from a terminal.

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
  first. The rights sheet says so when a space asks to launch pi.
- **OMP is only read**: launching it is left for after 1.0.
- **An agent started elsewhere is read-only**: something has no channel into a terminal it did not open. In 1.0, a
  Claude Code or Codex conversation can be continued in something ("continue here") once no other process holds it;
  OpenCode, pi and OMP conversations cannot.

A space reads what holds now in each agent's `can` and `because`, not in this table.

## Where it has run

*The suite has run on macOS 27 on Apple silicon, with Xcode 26 (Swift 6.3) and with the Command Line Tools 27 alone
(Swift 6.4, no Xcode), and only there so far. something requires macOS 15 (the package, the app and the formula say
so), the oldest macOS this repository's CI runs on: GitHub runs the suite at each push on macOS 15 and on the newest
macOS its runners offer, and installs the formula there with Homebrew; this line names them once those runs are
green.* Intel Macs are not tested.

## Uninstall

```sh
brew uninstall something
brew untap emiwltz/tap                               # if you installed nothing else from it
rm -rf ~/Library/Application\ Support/something      # your answers to the rights sheets, the journals
rm -rf ~/something                                   # your spaces and their memory: keep them if you may come back
rm -rf ~/Applications/something.app                  # the launcher, if the tour added it
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

With the Command Line Tools alone and no Xcode, `swift test` is proven with the Command Line Tools 27 only; GitHub
builds the tests with the older ones of its runners at each push.

The Homebrew formula is [packaging/homebrew/something.rb](packaging/homebrew/something.rb); the rules for changing
the code are in [AGENTS.md](AGENTS.md).

```text
share/                     something.js, the template, the templates and their previews, the skill, the guide, the contract as data
Sources/SomethingCore/     contract 1: the state, spaces, declarations, rights, the bridge, memory, journal, export, codes
Sources/SomethingAgents/   the engine, a driver per agent it launches, a reader per agent it reads
Sources/something/         the command and the Mac app: the window, its sidebar and Info, the open space, the sheets and panels that ask you
packaging/, tools/         the app's Info.plist, the Homebrew formula, make-app.sh, previews.sh (the templates' pictures)
.github/workflows/         the suite and a Homebrew install, run by GitHub at each push
Tests/                     the Swift suites, recorded exchanges with invented text, and the node tests of something.js
```

## Not done yet

- **A tagged version.** Until the first tag, `brew install` needs `--HEAD`.

## Security

something opens no port and listens on nothing; a space cannot reach the Internet (except the gap described in
[No network for spaces](#no-network-for-spaces)), nor draw the windows that ask you.
The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A
space is code your agent wrote: read what you open.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## License

[MIT](LICENSE).
