# something

something is a Mac app for **spaces**, pages of your own that you build with your own coding agent, such as a board of who is waiting
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

`something` opens with one welcome screen, alone on your desktop: a space (a page of your own), your agents, and your
assistant, beside one picture of how they meet. The coding agent found on your Mac is already chosen to build your
spaces ("Built by"; change it there if you like, it starts none of them), and one button, Make My First Space, opens
the window. Notifications and, when installed with Homebrew, a small launcher in `~/Applications` so that Spotlight
finds something stay off until you turn them on in Settings › General. Help › Welcome shows the welcome again, and
Help › How something Works the picture, one part at a time if you like.

The welcome ends on the blank page (New Space, ⌘N): **What do you want to make?** Describe a space (a suggestion fills
the field with an example), choose under it what it may do with your agents (None, Watch, Talk or Run, pre-set from
your words), and Build: your agent builds it, and it opens by itself when ready, with nothing more to allow. The space
appears in the sidebar at once, with a ring that fills as it builds; you may leave New Space meanwhile, or build
several at a time: nothing stops them, and a click on the row shows the build again. A space that finishes while you
are elsewhere says "… is ready · Open" (and a notification of the Mac too while something is in the background, if you
turned notifications on). Its assistant is asked to answer in two sentences, what is ready and one thing to try;
the card then shows your words, one line of what was made and checked, and that answer; the steps and anything longer
are folded under Details. A build that fails, or that you stop, keeps your words and their level on New Space to try
again. Each space's
assistant rests over it as a small sticker in a corner, whose eyes say what it does; drag it to the other side if it is
in the way. Click it (or ⌘K) to ask for a change: the space reloads as your agent saves it. The first time, a small
hint says so beside it; Info and Point each have one too, once, at a later opening. ⌘J shows the conversation,
⌘\ makes it small again, ⌘. stops the assistant. Its one chip, "Claude Code · Sonnet 5.5", changes the agent, the model
and the effort of that space's conversation: models go by the names the agent gives them, and a kind something has not
run yet says "Its models show after its first run". "/" at the start of its field lists the agent's own commands as
the agent lists them (↑↓, Return sends one as you wrote it, Tab leaves it for its text); something remembers each
agent's list for the next time it is not running. Templates (⇧⌘T) are six finished spaces to start from, and need no
agent. ⌘P goes or asks: type a space's name to go there, or a sentence for an assistant. The line "Goes to" says once
where it goes (this space, a New Space built from it, or another space), Tab changes it, and nothing is sent before
Return. ⌘/ lists the shortcuts.

**One assistant per space**: each space has its own conversation with your agent, so several can work at once, each on
its own space. The sidebar lists your spaces by name, in groups you make; **Needs You**, at its top, lists the spaces
whose agents wait for your answer (each stays in its group too). The toolbar holds only the space's name (click it for
Info), Point, Info and Page Full Screen (⇧⌘F: the page fills the window, the toolbar comes back at its top edge, Esc
leaves); Reload is in the View menu (⌘R). Hide the sidebar (⌃⌘S) and it floats: rest the pointer on the window's left
edge and it comes over the page, its pin keeps it. **something stops
idle assistants on its own** to save memory: one idle for 10 minutes falls asleep, and at most 3 stay awake (the open
space's, and any that works or waits for you, are never put to sleep). Settings (⌘,), Assistant, changes both: Put
idle assistants to sleep after, and Keep at most; Put Idle Assistants to Sleep (Assistant menu) does it at once. A
sleeping assistant wakes on your next message and picks its conversation up, unless Resume each space's conversation is
off in the same pane, kept in `~/Library/Application Support/something/assistants/`: its agent, model, effort and last
60 items. An agent that cannot resume a conversation (all but Claude Code for now) is never put to sleep on its own; put
to sleep by you, it starts a new conversation, and says so.

**Quick Change**: point at a part of a space (⌥⌘S), say what should change, and press Return. A temporary session of
that space's assistant, the same agent with the same model and effort, makes the change while the space's own
conversation stays as it was; a message you write to it meanwhile waits until the Quick Change ends. something stops
the temporary session once its turn ends, never while one of its requests waits for you. Each Quick Change leaves a
new conversation in your agent's own history, which something does not clean.

**Comments**: while you point, Add Comment (⌘↵) keeps what you say about a part as a numbered pin instead. Point at
other parts, comment on each, then Send to Assistant (⌘↵): they go together, in one message, to the space's own
assistant, which works through them. A comment stays editable until it leaves, and comes back if that turn is stopped.

A Quick Change that changes nothing leaves its answer as a note beside the part. After each change a short note names
it, with Undo (⌘Z); Redo (⇧⌘Z) puts it back.

A space's past is kept as **versions** in `~/Library/Application Support/something/versions/`, never in the spaces
folder: after each change, its files, each content stored once, named by the sentence that asked for it, or "Edited
outside something" when no turn of its assistant made it. History (in Info, ⌘I, or View › Show History…) lists them with
a picture of each; hold one (or press Space) to see it over the page, let go to come back. Restore This Version is
itself a version, undone by ⌘Z, and the files it did not have go to the Trash. 50 versions per space and 500 MB in all
are kept by default; the oldest go first, never a space's latest, its files or its memory. A space heavier than 15 MB or
500 files keeps no versions; restoring it sends the files it changes to the Trash. A space moved to the Trash takes its
versions with it, and a space deleted or renamed in Finder sends the versions left under its old name there too, so a
new space of that name starts without them.

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
| Antigravity | by its process | no: Antigravity needs its own Google sign-in, so something shows it but doesn't build with it. | no |
| Amp | by its process | yes | yes |
| Cursor | by its process | no: Cursor would ask you before every small step of a build, so something shows it but doesn't build with it. | no |
| Auggie (`auggie`), Crush (`crush`), DeepSeek Harness (`dsh`), Factory Droid (`droid`), Gemini CLI (`gemini`), GitHub Copilot CLI (`copilot`), Goose (`goose`), Qwen Code (`qwen`), ZCode (`zcode`) | by its process | no: something has no extension for them. | no |

Amp keeps its conversations on its own servers, so an Amp you started yourself is seen by its process only. An agent
started elsewhere is read-only; a Claude Code or Codex conversation can be continued in something once no other
process holds it. What each driven agent cannot do (OpenCode and OMP cannot take a message during a turn, pi has no
mode, Amp cannot be interrupted) is in [the guide](share/guide.md#what-each-kind-can-do-and-what-it-cannot).

## The promise

something never answers for you. Your assistant may change your spaces and run something's own commands without
asking; everything else it does asks you, as your agent's own settings decide.

Your assistant is the agent you chose, working in `~/something/spaces`. Each space has its own: its own conversation
with that agent, started at its first message and shown when the space is open. New Space has one too, and the space it
makes keeps that conversation; a space moved to the Trash takes its conversation with it. something lends it three of
its own commands as tools (`something_guide`, `something_new`, `something_check`) through `something mcp`, an MCP server
(Model Context Protocol, the standard way to give an agent tools) that the agent starts for that conversation only; pi
runs them in its shell instead. What "without asking" means for each:

- **Claude Code**: edits and writes in `~/something/spaces`, and those three tools. Anything else asks you.
- **Codex**: its own sandbox, "workspace-write": files and commands in `~/something/spaces`, without the network, and
  those three tools. What the sandbox blocks asks you.
- **OpenCode** asks as your OpenCode settings say. **OMP** too, and its own default asks nothing.
- **pi** and **Amp** never ask when something launches them, by design (a tool your Amp settings would ask for, Amp
  refuses by itself): they can run any command on your Mac. The first lines of each conversation say so, and so does a
  space's Run, where you choose it and in Info.

"Ask Before Every Change", in the assistant card's menu or Settings › Permissions, turns the exception off from the next
conversation. No space can see what you say to your assistant, or write to it. something writes `AGENTS.md` and
`CLAUDE.md` in `~/something/spaces` to tell your assistant what something is; a copy whose first line you removed is
yours and left alone.

## Permissions

Every decision is yours, in a window of the Mac that a space cannot draw, imitate or answer:

- **Rights.** A space works with your agents at one level: **None**; **Watch**, it sees them (their state, folder and
  last messages); **Talk**, it also writes to them (a message, stop one, change its model); **Run**, it also starts one
  in a folder you pick. On New Space you choose it before Build, pre-set from your words: that choice is your consent,
  and the space opens without asking. A space made elsewhere (a template, an import, an agent outside something) asks
  for its level in a sheet at its first opening, pre-set to what it declares. What a space declares above its level
  stays refused, without asking again. Its memory needs no permission: it stays with the space. Info (⌘I), a panel
  beside the space, says it all in three parts: the space (its file, its size, Export, History), your agents (its
  level, one control that changes it at once, Run's folder, and the agents it shows now) and its assistant (its agent
  and model, its last reply, Open Conversation).
- **Permissions.** Each permission an agent something launched asks for opens a panel: "Allow Once" or "Deny". There is
  no "always". A space sees that the agent waits, and can never answer. One question is answered elsewhere: the one your
  assistant asks while it builds, which New Space shows with its choices while it shows that build (elsewhere, it is
  the panel's); its permissions still open the panel, across the window's top right corner. The Dock's badge counts every request waiting, and the sidebar's Needs You
  lists the spaces they come from; while something is in the background, its icon bounces once for each new one. A notification of
  the Mac says who waits and in which space only if you turn on "Notify me when a request waits", and never the command.
- **Modes.** A mode that makes an agent ask less always asks you again. A mode that never asks (Claude Code's
  `bypassPermissions`) is refused.
- **Links.** Each link a space opens asks you first.
- **Keys.** something's own shortcuts (⌘P, ⌘K, ⌘I, ⌘. and the others
  [the guide](share/guide.md#what-the-person-sees-of-your-space) lists) reach its menus even while a space has the
  focus: a page cannot keep them, so it cannot stop you from stopping your assistant.
- **Export.** An exported space carries its memory only if you choose so. Export, in Info or the Space menu, writes the
  space in one click as one `.something` file in your Downloads folder, without its memory, its level or its journal.

something reads each agent's own files read-only, and takes only what a space is shown. It writes nothing into your
agents' configuration: no hook, no MCP server, no skill, no setting. What a launch needs is passed on the command line
or the agent's channel, for that launch only. It writes only in `~/something/` and
`~/Library/Application Support/something/`, plus the exports you ask for in `~/Downloads`, the launcher in
`~/Applications` if you turn it on and the snapshots `something check` takes in `$TMPDIR/something-check`; what it
removes goes to the Trash.

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
rm -rf ~/Applications/something.app                  # the launcher, if you turned it on in Settings
rm -rf ~/Library/Application\ Support/something      # your settings, your spaces' levels, journals, versions and assistants' conversations
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

[MIT](LICENSE). The app bundles three fonts under the SIL Open Font License 1.1, each with its license in
[share/fonts](share/fonts): Fraunces (The Fraunces Project Authors), Onest (The Onest Project Authors) and Young
Serif (The Young Serif Project Authors).
