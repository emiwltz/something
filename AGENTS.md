# something: working rules

*For anyone who changes this repository, person or coding agent. Read this file, then [README.md](README.md): it says what something does, and it is the contract with the people who use it.*

## Who you work with

Emi maintains the project and gives the direction.

- **Talk to him in French, in plain words.** Explain a technical term the first time you use it. Start a report with where the goal stands and what comes back to him, before any detail.
- **He decides.** Bring him few decisions at a time, each with two to four options, what each implies, and your recommendation.
- **Propose, do not expand.** A possible improvement is a question to him; it does not add itself to the work.
- **Say what is true.** Keep decided, done, verified, proposed and blocked apart. Say what you did not verify and what went wrong.

If you work for a contributor, the same holds with them, in their language. What enters `main` is Emi's decision.

Everything in the repository is in English: code, comments, data keys, commit messages, documents.

## What must stay true

1. **Nothing in the agents.** something writes no hook, no MCP server, no skill and no setting into an agent's configuration. What a launch needs is passed on the command line or the agent's channel, to the agents something launches (the MCP server `something mcp` included).
2. **Every permission is shown.** A request from an agent something launched waits for a click in a window of the Mac: "Allow Once" or "Deny". A space cannot draw that window or answer it. One exception, Emi's decision of 19 Oct 2026: the assistant's own building work. The promise, in the same words in the README and the app: "something never answers for you. Your assistant may change your spaces and run something's own commands without asking; everything else it does asks you, as your agent's own settings decide." For Claude Code that is exactly edits and writes in `~/something/spaces` and the tools something lends it over MCP (`something_guide`, `something_new`, `something_check`, Lent.swift); its rules fail toward asking, never a broader path, a `Bash(...)` rule or a whole MCP server. "Ask Before Every Change" turns it off.
3. **The unknown is said.** What is not known is `null`; a state no source gives is `"unknown"`, never `"idle"`, never a guess.
4. **No orchestration.** something launches, shows and passes messages it is asked to pass. It never chains agents by itself, gives them roles, or decides for the person. The assistant is Emi's decision of 19 Oct 2026: the app launches the person's chosen agent in `~/something/spaces` to build spaces with them; it is a launch like any other, with the narrow pre-allowances of rule 2; no space can write to it or read its conversation.
5. **Nothing leaves the machine.** No telemetry, no connection to the Internet, from the app or from a space.
6. **Minimal.** Swift and the system's frameworks, no package dependency, no build step for spaces. Budgets, checked by `BudgetTests`: the core (`Sources/SomethingCore`) 1,800 lines in all; the host (`Sources/SomethingAgents`) 2,800 in all and 400 per file; in each `Sources/Agent*` target, each driver 600 and each other file 400; the Mac app (`Sources/something`) 5,500 in all, a soft budget that Emi may raise. An agent described only by data, without a driver of its own, takes at most 40 lines: none exists yet, so review checks it until the first one comes with its test. `TemplatesTests` keeps each template under 700 lines: an agent reads it as an example. Every line counts, comments too.
7. **Agents are extensions.** `SomethingCore` is contract 1 and knows no agent. `SomethingAgents` is the host: the engine, the watch, the programs, and what an agent provides (`AgentDescriptor`, `Driving`, `Driver`, `Reader`); no line of its code names an agent. Each agent family is one target that imports the host and never another family: `AgentClaude`, `AgentCodex`, `AgentACP` (one driver for every agent over the Agent Client Protocol, each agent a profile: OpenCode, OMP) and `AgentPi` (pi, and OMP's reader). What the host shares with them is `package`, never `public`, unless the app needs it. The app's `Extensions.swift` is the one file that lists them. An extension uses no force unwrap, `as!`, `try!`, `fatalError` or `precondition`, and neither imports Darwin nor calls what only Darwin has: `ExtensionRulesTests` checks it, and `ConformanceTests` feeds every registered driver and reader damaged input: a driver must say what it cannot read or leave it out, a reader must survive and return in time.
8. **Clear.** Each file has one role, said in its first comment. A public function says what it returns and when it throws. A comment says why, not what.

## The contract

What a space sees is the contract: the declaration block, the names of `something.js`, the keys of the state, the export format. It carries a number (`contract: 1`). Within a number, things are only added, never renamed or removed. The guide (`share/guide.md`) describes it, and the README links it. A change of behavior updates both in the same commit.

## Publishable

What is committed here is public, and stays in the history even when a later commit removes it.

- **Never in a file, a test, an example or a commit message:** a key, a token or any other secret; a home folder with a real name, a user or machine name, an e-mail address; a line of a real session, even one; the name or the path of someone's private project.
- **Examples are invented.** A path starts with `/Users/example`, an address ends with `example.com`, the texts are made up. Recorded exchanges come from test sessions whose content is invented.
- **`PublishableTests.swift` (in `Tests/`) checks what a scan can see**, in the files and in the commits not pushed yet. It runs with the suite. It cannot recognize session content: that part is on you.
- **If something personal was committed:** stop, do not push, tell Emi. A secret that was pushed is compromised: say it must be revoked.

## How to work

- **Remove first.** Before writing code: delete, reuse, document. Code comes last.
- **Small verified slices.** One commit per slice that is tested and works.
- **A choice nothing covers:** if it is implementation, take the smallest reversible option, note it in the commit, go on. If it changes what the product is or what the README promises, ask Emi.
- **Keep the paperwork small.** The documents are the README, this file, and the guide for spaces. No progress logs, no plan files.
- **Sub-agents:** at most two at a time (the suite and the builds are memory-hungry). One writer per file. An independent reviewer for anything that touches the core. A sub-agent does not inherit these rules: its brief gives the goal, the files it may touch, what is forbidden, and the proof expected, and tells it to work alone.

## Proving

```sh
swift build
swift test
node --test Tests/something-js.test.mjs    # name the file: node 22 does not take a folder
```

- **The Command Line Tools alone.** A newcomer has no Xcode, and Homebrew builds from source with the Command Line Tools when no bottle fits. On a Mac with Xcode, also run `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build`. Some SwiftUI attributes are macros whose plugin only Xcode ships (`@State`, `@Entry`): `ToolchainTests` allows only a list of attributes in `Sources/`, and a word joins it only after `Sources/` built with it under the Command Line Tools alone.
- **Fakes shaped exactly like real data.** Fake agents that speak each channel, fake session files with invented text. A fixture that does not match the real shape proves nothing.
- **A fresh environment after each commit**: the suite also passes from a clean clone with an empty home folder.

  ```sh
  tmp=$(mktemp -d) && git clone -q . "$tmp/clone" && mkdir "$tmp/home" &&
    (cd "$tmp/clone" && HOME="$tmp/home" swift test)
  code=$?; rm -rf "$tmp"; (exit $code)
  ```

- **Tests leave nothing behind.**
  - No test, trial or tool leaves an `.app` registered with LaunchServices: any `.app` is made under `$TMPDIR`, then unregistered (`lsregister -u`) and removed. `PackagingTests` checks that `lsregister -dump` names no `something.app` under `$TMPDIR`. No test runs Spotlight's importer (`mdimport` registers what it reads).
  - WebKit's folders cannot be deleted, so no test may make a new set: every `something check` a test runs is in-process, except in the builders' trials, which run a copy of the program stamped with a fixed build identity (`AssistantBuild.placeProgram`): WebKit names its folders after that identity, so they are made once per machine.
  - No test depends on the calendar: fixture times are relative to now, or the read takes `now:`.
  - Nothing goes to the real Trash: `Library.trash` goes through a seam the tests replace.
  - After each commit, these three counts are the same before and after one `swift test` and one clean-clone run: `ls -d $TMPDIR/com.apple.WebKit.*+something-* | wc -l`, `ls $TMPDIR | grep -c '^something'`, and `lsregister -dump | grep -c 'something.app'`.
- **Other machines.** GitHub runs the suite on macOS at each push (`.github/workflows/tests.yml`). A red run is fixed before anything else.
- **A virtual machine before a version is tagged:** the full trial of a newcomer, `brew install` included, on a fresh macOS.
- **Green tests do not replace a trial with real agents.** Readers are also checked, read-only, against real session files; drivers against the real programs.
- **Session content is private.** Never print it, log it, copy it outside the machine, or paste it in a report, an issue or a commit. Describe shapes, not content.

## Never without Emi

- Push, publish, install anything on his machine, or change a global configuration (an agent's settings, the shell).
- Make a repository public, change its settings, tag or release a version, rewrite a history that was pushed.
- Listen anywhere other than 127.0.0.1. A test listener binds 127.0.0.1 on a port the system picks (port 0) and stops
  when the test ends.
- Send anything to a real agent, or start, stop or close a real agent, a real terminal or a virtual machine.
- Read, show or copy a secret (`.env`, keys, tokens).
- Write, change or delete anything outside this repository, except a temporary folder you created yourself.
