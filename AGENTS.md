# something: working rules

*For anyone who changes this repository, person or coding agent. Read this file, then [README.md](README.md), the
promise to the people who use something, and [share/guide.md](share/guide.md), the contract with the pages it shows.*

## What it is

something is a Mac app (Swift, AppKit and WebKit) that shows **spaces**, HTML pages a person builds with their own
coding agent, locked off the network, and gives them a bridge (`something.js`) to see the coding agents on the Mac and
talk to them. It also launches the person's chosen agent as their assistant to build those spaces.

## Who you work with

Emi maintains the project and gives the direction.

- **Talk to him in French, in plain words.** Explain a technical term the first time you use it. Start a report with
  where the goal stands and what comes back to him, before any detail.
- **He decides.** Bring him few decisions at a time, each with two to four options, what each implies, and your
  recommendation.
- **Propose, do not expand.** A possible improvement is a question to him; it does not add itself to the work.
- **Say what is true.** Keep decided, done, verified, proposed and blocked apart. Say what you did not verify and what
  went wrong.

If you work for a contributor, the same holds with them, in their language. What enters `main` is Emi's decision.
Everything in the repository is in English: code, comments, data keys, commit messages, documents.

## Layout

```text
Sources/SomethingCore/     contract 1: the state, spaces, declarations, rights, the bridge, memory, journal, export, codes
Sources/SomethingAgents/   the host: the engine, the watch, the programs, the lent tools (Lent.swift), and what an agent
                           provides (AgentDescriptor, Driving, Driver, Reader in Extension.swift and Driver.swift)
Sources/Agent*/            one target per agent family: AgentClaude, AgentCodex, AgentACP (one driver for the Agent
                           Client Protocol, a profile per agent: OpenCode, OMP, Cursor; and Antigravity's descriptor),
                           AgentPi (pi, and OMP's reader), AgentAmp
Sources/something/         the command and the Mac app; Extensions.swift is the only list of the agents
share/                     what the app reads at run time: something.js, the templates, the guide, the skill, the
                           assistant's AGENTS.md, the contract as data (share/contract/)
Tests/                     the Swift suites; Fixtures/ (invented agent homes the readers read); Exchanges/ (recorded
                           exchanges, invented text); something.js's tests. somethingTests links three helpers from
                           SomethingAgentsTests (AssistantBuild, FakeMessagesAPI, LeavesNothing): change them there
packaging/, tools/         Info.plist, the icon, the Homebrew formula and the tap's files, make-app.sh, previews.sh
```

## Adding an agent

1. **Its descriptor** (`AgentDescriptor`): its kind, name, install sentence, what it never does, and why something
   does not launch it (`unavailable`) when it does not. Pure data.
2. **How it is driven**, if it is: an agent that speaks ACP is an `ACPProfile` in `AgentACP` (data and a few small
   closures); any other is a `Driving` and a `Driver` in its family's target, or in a new `Agent<Name>` target added
   to `agents` in `Package.swift`. A reader of its files, if something can read them; else `OtherReader` sees its
   process.
3. **Register it** in `Sources/something/Extensions.swift`, add its kind to `share/contract/shape.json`, and update the
   README's table of agents and the guide (its kinds and limits); the tests hold the shape and the README's table to
   the registry.
4. **A driven agent is a builder.** Add its kind to `Tests/Exchanges/driven.txt` with a recorded build
   (`Tests/Exchanges/<kind>/assistant-build.jsonl`, from a test session with invented text, see "Trials") that makes
   and checks a space without asking the person. An agent that cannot is only seen, with its reason.

## What must stay true

1. **Nothing in the agents.** something writes no hook, no MCP server, no skill and no setting into an agent's
   configuration. What a launch needs is passed on the command line or the agent's channel, for that launch only.
2. **Every permission is shown.** A request from an agent something launched waits for "Allow Once" or "Deny" in a
   window of the Mac, which a space cannot draw or answer. One exception, the assistant's own building work, with the
   same words in the README and the app: "something never answers for you. Your assistant may change your spaces and
   run something's own commands without asking; everything else it does asks you, as your agent's own settings
   decide." For Claude Code that is exactly edits and writes in `~/something/spaces` and the lent tools; its rules fail
   toward asking, never a broader path, a `Bash(...)` rule or a whole MCP server. "Ask Before Every Change" turns it
   off.
3. **The unknown is said.** What is not known is `null`; a state no source gives is `"unknown"`, never `"idle"`, never
   a guess.
4. **No orchestration.** something launches, shows and passes the messages it is asked to pass. It never chains agents,
   gives them roles, or decides for the person. The assistant is a launch like any other; no space can write to it or
   read its conversation.
5. **Nothing leaves the machine.** No telemetry, no connection to the Internet, from the app or from a space.
6. **Minimal.** Swift and the system's frameworks, no package dependency, no build step for spaces. Budgets, checked by
   `BudgetTests`, every line counted: the core 1,850 lines in all; the host 2,750 in all and 450 per file; in each
   `Agent*` target, 650 per driver and 450 per other file; the app 5,500 in all, a soft budget Emi may raise; an agent
   described only by data, 40 lines. `TemplatesTests` keeps each template under 700 lines.
7. **Agents are extensions.** `SomethingCore` knows no agent. No line of the host's code names one. A family imports
   the host and never another family; what the host shares with them is `package`, public only where the app needs
   it. An extension uses no force unwrap, `as!`, `try!`, `fatalError` or `precondition`, and nothing only Darwin has
   (`ExtensionRulesTests`); `ConformanceTests` feeds every driver and reader damaged input.
8. **Clear.** Each file has one role, said in its first comment. A public function says what it returns and when it
   throws. A comment says why, not what.

**The contract.** What a space sees (the declaration, the names of `something.js`, the keys of the state, the codes,
the export format) is contract 1. Within it, things are only added, never renamed or removed. A change of behavior
updates the guide, and the README if it changes the promise, in the same commit.

## Publishable

What is committed here is public, and stays in the history even when a later commit removes it.

- **Never in a file, a test, an example or a commit message:** a key, a token or any other secret; a home folder with a
  real name, a user or machine name, an e-mail address; a line of a real session; the name or path of someone's
  private project.
- **Examples are invented.** A path starts with `/Users/example`, an address ends with `example.com`. Recorded exchanges
  come from test sessions whose content is invented.
- **`PublishableTests`** checks what a scan can see, in the files and in the commits not pushed yet. It cannot
  recognize session content: that part is on you.
- **If something personal was committed:** stop, do not push, tell Emi. A secret that was pushed is compromised: say it
  must be revoked.

## How to work

- **Remove first.** Before writing code: delete, reuse, document. Code comes last.
- **Small verified steps.** One commit per step that is tested and works.
- **A choice nothing covers:** if it is implementation, take the smallest reversible option, note it in the commit, go
  on. If it changes what the product is or what the README promises, ask Emi.
- **Keep the paperwork small.** The documents are the README, this file and the guide. No progress logs, no plan files.
- **Sub-agents:** at most two at a time (the suite and the builds are memory-hungry), one writer per file, an
  independent reviewer for anything that touches the core. Their brief gives the goal, the files they may touch, what is
  forbidden, the proof expected, and tells them to work alone.

## Proving

```sh
swift build
swift test
node --test Tests/something-js.test.mjs    # name the file: node 22 does not take a folder
```

`perl -e 'alarm 900; exec @ARGV' swift test` stops a hung run after 15 minutes (CI stops it after 20). A hang usually
means a test reached a real program, which `TestRunGuard` should have refused.

- **The Command Line Tools alone.** A newcomer has no Xcode. On a Mac with Xcode, also run
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build`. Some SwiftUI attributes are macros only Xcode ships
  (`@State`, `@Entry`): `ToolchainTests` allows only a list of attributes in `Sources/`, and one joins it only after
  `Sources/` built with it under the Command Line Tools alone.
- **A fresh environment after each commit**: the suite also passes from a clean clone of that commit with an empty home.

  ```sh
  tmp=$(mktemp -d) && git clone -q . "$tmp/clone" && mkdir "$tmp/home" &&
    (cd "$tmp/clone" && git checkout -q <commit> && HOME="$tmp/home" swift test)
  code=$?; rm -rf "$tmp"; (exit $code)
  ```

- **Fakes shaped exactly like real data.** Fake agents that speak each channel, fake session files with invented text.
- **Other machines.** GitHub runs the suite on macOS 15 and its latest macOS at each push (`.github/workflows/tests.yml`).
  A red run is fixed before anything else.
- **Green tests do not replace a trial with real agents.** Readers are also checked, read-only, against real session
  files; drivers against the real programs. Session content is private: never print it, log it, copy it off the
  machine, or paste it anywhere. Describe shapes, not content.

**Trials**, with real agents, run only when asked, each in a throwaway home with a fake model and a made-up key; the
header of each `*Trial.swift` says what it proves.

- `SOMETHING_TRIAL_<KIND>=<program>` (CLAUDE, CODEX, OPENCODE, PI) runs that kind's trials, for example
  `SOMETHING_TRIAL_CLAUDE=/opt/homebrew/bin/claude swift test --filter ClaudeTrial` (also `ClaudeReaderTrial`,
  `AssistantTrial`, `CodexTrial`, `OpenCodeTrial`, `PiTrial`, `ReadersTrial`).
- `SOMETHING_TRIAL_RECORD=<folder>` also writes each case as an exchange, paths made `/Users/example`: the raw
  material of `Tests/Exchanges`. `something try <kind> [--record <file>] [--plan-b] [--assistant]` drives one agent
  by hand from a terminal; record only a throwaway session whose text is invented.
- `SOMETHING_TRIAL_REAL_<KIND>=1` (CLAUDE, CODEX, OPENCODE, PI, OMP) and `SOMETHING_TRIAL_COST=1` read this Mac's
  own sessions, read-only, and print counts only. `SOMETHING_TRIAL_REST=1` measures the app's timers at rest.
- `SOMETHING_GALLERY=<folder> swift test --filter GalleryTests` draws every window to PNGs, to look at.
  After changing a template, run `tools/previews.sh` and commit its pictures.

**Tests leave nothing behind.**

- Any `.app` is made under `$TMPDIR`, then unregistered (`lsregister -u`) and removed; `PackagingTests` checks that
  `lsregister -dump` names no `something.app` under `$TMPDIR`. No test runs `mdimport`.
- WebKit's folders cannot be deleted: every `something check` a test runs is in-process, except in the builders'
  trials, which run a copy stamped with a fixed build identity (`AssistantBuild.placeProgram`).
- No test depends on the calendar, reaches a real agent or the installed app, or puts anything in the real Trash
  (`Library.trash` goes through a seam). A test listener binds 127.0.0.1 on port 0 and stops when the test ends.
- These counts are the same before and after one `swift test` and one clean-clone run:
  `ls -d $TMPDIR/com.apple.WebKit.*+something-* | wc -l`, `ls $TMPDIR | grep -c '^something'`,
  `lsregister -dump | grep -c 'something.app'`.

## Releasing

Emi's gesture, after the full trial on a fresh virtual machine (below).

1. Tag `vX.Y.Z` on `main` and push the tag; `shasum -a 256` the tag's tarball from GitHub.
2. Put that url and sha256 in both formulas, `packaging/homebrew/something.rb` and `packaging/homebrew/tap/Formula/`
   (`PackagingTests` keeps them alike), and in the tap formula's `root_url` comment.
3. Open a pull request on `emiwltz/homebrew-tap` with the tap formula; its `tests.yml` builds the bottles.
4. Once it is green: `gh workflow run publish.yml -R emiwltz/homebrew-tap -f pull_request=<number>`.
5. Then run the tap's `install.yml` by hand, and check `brew install emiwltz/tap/something` on a clean Mac.
6. Update the README: "The version in Homebrew" and "Where it has run". The tap's workflows are copies of
   `packaging/homebrew/tap/.github/workflows/`: change both together.

## Never without Emi

- Push, publish, install anything on his machine, or change a global configuration (an agent's settings, the shell).
- Make a repository public, change its settings, tag or release a version, rewrite a history that was pushed. A
  version is tagged only after the full trial of a newcomer, `brew install` included, on a fresh macOS virtual machine.
- Raise a budget, or change what the README promises.
- Listen anywhere other than 127.0.0.1.
- Send anything to a real agent, or start, stop or close a real agent, a real terminal or a virtual machine.
- Read, show or copy a secret (`.env`, keys, tokens).
- Write, change or delete anything outside this repository, except a temporary folder you created yourself.
