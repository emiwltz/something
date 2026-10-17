# something v2

A Mac app you start with one command in the terminal. It opens a real window, launches your coding agents through their official channels, always shows you their permission requests, and lets your own agent draw the interface you want in that window.

It is young. Today it launches Claude Code, Codex, OpenCode or pi in a folder you choose, shows what they say, sends them your messages after asking you, and shows you their permission requests. Another agent that speaks ACP takes one line to add. The design file (in French, private) is the reference: https://claude.ai/artifact/GwPKPZoVZRASAzkF4ELbeR

It follows [something](https://github.com/emiwltz/something), which stays frozen as it is.

## Run

Needs a Mac with Apple's command line tools (`xcode-select --install`, free; already there if `git` works). Xcode itself is not needed. Then, for each agent you want to launch, that agent installed and signed in as you use it in a terminal: `claude`, `codex`, `opencode`, `pi`.

```sh
swift run something                 # builds, then opens the window and the menu bar icon
swift run something --self-test     # checks the window is on screen, ⌘V pastes, the page answers, its memory works, the network is closed
swift run something --try claude --in /Users/example/scratch   # launches Claude Code (or codex, opencode, pi) there, sends one short message, prints what came back
# add --ask "<message>" to send your own; --answer once|deny answers its permission requests without a window,
# --click "<button>" shows the windows and has something click that button itself; --force-ask makes Codex and OpenCode ask before acting; --model <model> picks OpenCode's or pi's model for the conversation
swift test                          # the tests of the core (with Xcode installed; without it, see below)
```

Nothing is signed with a paid Apple account: what is built on the machine itself is not blocked by macOS.

With the command line tools alone, Swift Testing is installed but `swift test` does not find it by itself; give it the way:

```sh
T=/Library/Developer/CommandLineTools/Library/Developer
swift test -Xswiftc -F -Xswiftc $T/Frameworks -Xlinker -F -Xlinker $T/Frameworks \
  -Xlinker -rpath -Xlinker $T/Frameworks -Xlinker -rpath -Xlinker $T/usr/lib
```

## Pages

For now the window shows one page, `share/template.html`, a plain chat; spaces of your own, written by your coding agent, come next. The guide written for that agent is [share/guide.md](share/guide.md). The page reloads each time its file is saved. It loads its files from `something://` addresses and cannot reach the Internet. It has a small memory of its own, `~/something/data/template.json`.

## The first page

In the window, "Launch Claude Code…", "Launch Codex…", "Launch OpenCode…" or "Launch pi…" asks for a folder, then the page shows the agent, its model and its messages. Each message you write is shown to you in a window of the Mac before it leaves ("Send", "Always for this agent", "Don't send"): a page can read, writing is your word. Closing the window keeps something in the menu bar with its agents; quitting stops them, after asking.

When an agent asks before acting ("may it write hello.txt?", "may it run this command?"), something shows the question in a window of the Mac: "Allow once" or "Deny" (also Escape). There is no "always": something never writes a lasting rule into an agent's settings. An agent asks only what its own settings do not already allow (Claude's permission mode, Codex's approval policy, OpenCode's permissions), so your settings are respected as they are. The page shows that the agent waits, but cannot answer for you.

Claude Code is launched as `claude -p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio`, the channel Anthropic's SDKs use (the last option is what the SDKs pass to receive permission requests; Claude's help does not list it). It runs with your own Claude Code settings, in the folder you chose, without `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` from your environment, so that it uses the account you signed in with.

Codex is launched as `codex app-server`, its official JSON-RPC channel, one private server per conversation, with your own Codex configuration. something never joins the server a Codex in your terminal may share.

OpenCode is launched as `opencode acp`: it speaks ACP, the Agent Client Protocol, which other agents speak too. One conversation per program, with your own OpenCode configuration.

pi is launched as `pi --mode rpc`, its official channel, with your own pi configuration. pi never asks permission, by design: there is nothing to show.

## How it is made

```text
share/                     what the window serves: something.js (the tools a page uses), template.html (the page shown), guide.md (the guide for the agent that writes pages)
Sources/SomethingCore/     the state, the bridge, the page memory: Foundation only, names no agent, so it can build on Linux and Windows
Sources/SomethingAgents/   one driver per agent (AgentProcess, Claude, Codex, ACP, Pi)
Sources/something/         the Mac app: menu bar, window, something:// pages, native windows; carries, asks, decides nothing
Tests/                     SomethingCoreTests (with the budgets and the publishable scan) and SomethingAgentsTests
```

A page talks to something with one protocol: it sends `{"method": ..., "params": ...}` and gets `{"result": ...}` or `{"error": ...}`. What is not known is `null`, never missing and never a guess. Another machine would need only a new shell around the same core and the same pages.

This repository is local and private: it has no remote.

## Security

something opens no port and listens on nothing: the window and the agents talk inside the app. A page cannot reach the Internet, and cannot draw the windows that ask you: every message to an agent, and every permission an agent asks, waits for your click. The agents run as you, with your own settings, in the folder you chose: give something the trust you give them. A page is code your agent wrote: read what you open.

To report a weakness without making it public, use "Report a vulnerability" in the Security tab of the repository.

## License

[MIT](LICENSE).
