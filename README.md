# something

something is a Mac app for **spaces**: pages you build with your own coding agent, such as a board of who is waiting
for you, a morning paper of what your agents did, or a small game for your breaks. something shows them safely, and
lets them see the coding agents on your Mac and talk to them.

*This page describes `main`. The version in Homebrew is 0.2.0, which drives fewer agents (Claude Code, Codex,
OpenCode, pi); `brew install --HEAD emiwltz/tap/something` builds `main` from source instead (a few minutes).*

## Install

You need a Mac with macOS 15 or later and [Homebrew](https://brew.sh). No Xcode: Homebrew pours a version built in
advance for your Mac, or where none fits, builds one with Apple's Command Line Tools.

```sh
brew install emiwltz/tap/something
something
```

## The first minutes

`something` opens its window. A short tour says what something is and asks which of your installed coding agents
builds your spaces with you (it starts none of them). It also offers a small launcher in `~/Applications`, so that
Spotlight finds something.

The tour ends on the blank page (New Space, ⌘N): **What do you want to make?** Describe a space, or click a suggestion,
and your agent builds it; it opens by itself when ready, and a sheet asks you what it may do. Ask for changes in the bar
at the bottom of the window: the space reloads as your agent saves it. ⌘K types to the agent, ⌘J shows the
conversation, ⌘. stops it. Templates (⇧⌘T) are six finished spaces to start from, and need no agent.

Your agent must be installed and signed in as you use it in Terminal: something uses your own account and settings.

## Agents

Each agent something knows is **seen** (its files are read, or only its running program), **driven** (launched and
talked to through its own official channel) and a **builder** (it can build your spaces with you), or says why not.
Every agent something drives is also a builder.

| | seen | driven | builder |
|---|---|---|---|
| Claude Code | yes | yes | yes |
| Codex | yes | yes | yes |
| OpenCode | yes | yes | yes |
| pi | yes | yes | yes |
| OMP | yes | yes | yes |
| Antigravity | by its process | no: Antigravity's ACP server needs a Google sign-in of its own first; something only sees agy for now. | no |
| Amp | by its process | yes | yes |
| Cursor | by its process | no: Cursor asks you before each of something's own tools, so something only sees cursor-agent for now. | no |
| Auggie (`auggie`), Crush (`crush`), DeepSeek Harness (`dsh`), Factory Droid (`droid`), Gemini CLI (`gemini`), GitHub Copilot CLI (`copilot`), Goose (`goose`), Qwen Code (`qwen`), ZCode (`zcode`) | by its process | no: something has no extension for them. | no |

Amp keeps its conversations on its own servers, so an Amp you started yourself is seen by its process only. An agent
started elsewhere is read-only; a Claude Code or Codex conversation can be continued in something once no other
process holds it. What each driven agent cannot do (OpenCode and OMP cannot take a message during a turn, pi has no
mode, Amp cannot be interrupted) is in [the guide](share/guide.md#what-each-kind-can-do-and-what-it-cannot).

## The promise

something never answers for you. Your assistant may change your spaces and run something's own commands without
asking; everything else it does asks you, as your agent's own settings decide.

Your assistant is the agent you chose, working in `~/something/spaces`. something lends it three of its own commands
as tools (`something_guide`, `something_new`, `something_check`) through `something mcp`, an MCP server (Model Context
Protocol, the standard way to give an agent tools) that the agent starts for that conversation only; pi runs them in
its shell instead. What "without asking" means for each:

- **Claude Code**: edits and writes in `~/something/spaces`, and those three tools. Anything else asks you.
- **Codex**: its own sandbox, "workspace-write": files and commands in `~/something/spaces`, without the network, and
  those three tools. What the sandbox blocks asks you.
- **OpenCode** asks as your OpenCode settings say. **OMP** too, and its own default asks nothing.
- **pi** and **Amp** never ask when something launches them, by design (a tool your Amp settings would ask for, Amp
  refuses by itself): they can run any command on your Mac. The tour and the bar say so.

"Ask Before Every Change", in the bar's agent menu, turns the exception off from the next conversation. No space can
see what you say to your assistant, or write to it. something writes `AGENTS.md` and `CLAUDE.md` in
`~/something/spaces` to tell your assistant what something is; a copy whose first line you removed is yours and left
alone.

## Permissions

Every decision is yours, in a window of the Mac that a space cannot draw, imitate or answer:

- **Rights.** At the first opening of a space, a sheet lists what it declares (see your agents, write to them, start
  them, remember things), each to allow or not. Info (⌥⌘I) shows each right with a switch to revoke it, and what the
  space did.
- **Permissions.** Each permission an agent something launched asks for opens a panel: "Allow Once" or "Deny". There
  is no "always". A space sees that the agent waits, and can never answer.
- **Modes.** A mode that makes an agent ask less always asks you again. A mode that never asks (Claude Code's
  `bypassPermissions`) is refused.
- **Links.** Each link a space opens asks you first.
- **Export.** An exported space carries its memory only if you choose so.

something reads each agent's own files read-only, and takes only what a space is shown. It writes nothing into your
agents' configuration: no hook, no MCP server, no skill, no setting. What a launch needs is passed on the command line
or the agent's channel, for that launch only. It writes only in `~/something/` and
`~/Library/Application Support/something/`.

## No network for spaces

A space loads only its own files, inline code, `data:` and `blob:`. Every other address is blocked four times: a
sandboxed frame, a content security policy, a content rule list, and a navigation policy. The app opens no port,
listens on nothing and sends no telemetry.

One gap is known. When you click with the mouse on a link that opens a new window (`target="_blank"`) inside a closed
shadow root written in HTML, WebKit may look up the link's server name and open one connection to it before it refuses
the window. No request is sent, but the page chooses the name, so it could put a few words in it. Every other link is
stopped before any connection.

## Building spaces

The contract a space can rely on is [share/guide.md](share/guide.md), written for the coding agent that builds spaces
(`something guide --print` prints it; `something --help` lists the commands). To build spaces with an agent outside
something, give it the guide, or add [share/skill/SKILL.md](share/skill/SKILL.md) to your agent yourself.

## Uninstall

Quit something first (⌘Q): quitting stops the agents it launched.

```sh
brew uninstall something
brew untap emiwltz/tap                               # if you installed nothing else from it
rm -rf ~/Applications/something.app                  # the launcher, if the tour added it
rm -rf ~/Library/Application\ Support/something      # your answers to the rights sheets, the journals
rm -rf ~/something                                   # your spaces and their memory: keep them if you may come back
rm -rf "$TMPDIR/something-check"                     # the snapshots something check took of pages elsewhere
```

macOS and WebKit may also have made folders named after the app's identifier:
`find ~/Library -maxdepth 2 -name 'io.github.emiwltz.something*'` lists them.

## Building from the clone

The Command Line Tools are enough; Xcode is not needed.

```sh
git clone https://github.com/emiwltz/something && cd something
swift build
swift test                                  # the Swift suite
node --test Tests/something-js.test.mjs     # something.js against the contract's cases
swift run something                         # the app, in the terminal's own process
tools/make-app.sh <prefix> <version>        # assembles <prefix>/something.app, signed ad hoc, as the formula does
```

With `SOMETHING_HOME=<absolute folder>`, something (the app, its commands and its MCP server) keeps its folders there
instead of your home: `<folder>/something/spaces` and `<folder>/Library/Application Support/something`. The agents it
launches keep your real home and their sign-in. Never run `swift run something` and an installed something together:
both would launch agents and write the same journals. The rules for changing the code are in [AGENTS.md](AGENTS.md);
the Homebrew formula and the tap's files are in [packaging/homebrew/](packaging/homebrew).

## Where it has run

The suite has run on macOS 27 with the Command Line Tools 27 alone (Swift 6.4); at each push GitHub runs it on macOS
15 and on its latest macOS runner, and installs the formula there with Homebrew. The bottles of 0.2.0 are built and
installed on macOS 26 and 15 (Apple silicon) and macOS 15 on Intel; the suite itself has not run on an Intel Mac.

## Security

The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A
space is code your agent wrote: read what you open. To report a weakness privately, use "Report a vulnerability" in
the Security tab of the repository.

## License

[MIT](LICENSE).
