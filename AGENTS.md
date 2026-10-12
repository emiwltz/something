# something: working rules

*For anyone who changes this repository, person or coding agent. Read this file, then [README.md](README.md): it says what something does, what it serves and how an extension is written, and it is the contract with the people who use it.*

## Where the project stands

something works on its author's machine. The work now is to make it usable by someone else: a stranger, on another machine, with other agents installed, who has the README and nothing more. Every change is judged from that person's seat.

## Who you work with

Emi maintains the project and gives the direction.

- **Talk to him in French, in plain words.** Explain a technical term the first time you use it. Start a report with where the goal stands and what comes back to him, before any detail.
- **He decides.** Bring him few decisions at a time. Each one: two to four options, what each implies in practice, and your recommendation.
- **Propose, do not expand.** A possible improvement is a question to him. It does not add itself to the work he asked for.
- **Say what is true.** Keep decided, done, verified, proposed and blocked apart. Say what you did not verify and what went wrong.

If you work for a contributor, the same holds with them, in their language. What enters `main` is Emi's decision.

Everything in the repository is in English: code, comments, data keys, commit messages, documents.

## What must stay true

Three priorities, in this order.

1. **Stable.** A failure is visible. Nothing false is shown as true: what is not known is `null`, never zero and never a guess.
2. **Minimal.** Python standard library, JavaScript without dependency, no build step, no install step, no settings file, no database. The core (`something/`) stays small enough to read in one sitting: its budget is 800 lines, and raising it is Emi's decision. An extension aims for under 400 lines.
3. **Clear.** Each file has one role, said at its top. The core knows Herdr and names no harness: anything specific to one harness lives in its extension.

something is not an agent system: no coordinator, no roles, no memories, no orchestration. An idea of that kind is proposed to Emi; it is not added.

## Publishable

What is committed here is public, and stays in the history even when a later commit removes it.

- **Never in a file, a test, an example or a commit message:** a key, a token or any other secret; a home folder with a real name, the user name or the name of a machine, an e-mail address; a line of a real session, even one; the name or the path of someone's private project.
- **Examples are invented.** A path starts with `/Users/example`, an address ends with `example.com`, the texts are made up.
- **`tests/test_publishable.py` checks what a scan can see**, in the files and in the commits that are not pushed yet. It runs with the suite, before each commit. It cannot recognize session content: that part is on you.
- **If something personal was committed:** stop, do not push, tell Emi. Rewriting the history is his decision. A secret that was pushed is compromised, whatever is done afterwards: say that it must be revoked.
- **Before a push**, which is Emi's gesture: tell him whether the repository is public or private, and that the suite is green.
- **When the repository goes public**, Emi turns on in its GitHub settings: secret scanning with push protection, and private vulnerability reporting (README, "Security", relies on it). The tests become a required check on `main` at the first tag, when changes start to come through branches: before that, commits go straight to `main`, and such a check would refuse them.

## For the person who arrives

- **The first five minutes work from the README alone:** clone, `python3 -m something --example`, open the page. Nothing to install. A change that would add a step there is Emi's decision.
- **An error says what happened and what to do next,** in one sentence a newcomer understands, without a stack trace.
- **The README is the contract.** A change of behavior updates it in the same commit. Once a version is tagged, what it promises (the keys of the state, the routes, the tools of `something.js`, what an extension declares) only grows: removing or renaming is a new version, and Emi's decision.
- **Only name a platform where the suite has run.** The README says which ones.
- **Code is read more often than it is written.** A public function says what it returns and when it raises. A comment says why, not what. A name that needs a comment is renamed.

## How to work

- **Remove first.** Before writing code, look in this order: delete, reuse what exists, document. Code comes last.
- **Small verified slices.** One commit per slice that is tested and works. Until the first tag, commits go on `main`; after it, one branch per change, and merging into `main` is Emi's decision.
- **When you hit a contradiction or a choice nothing covers:** if it is a matter of implementation, take the smallest reversible option, note it in the commit, and go on. If it changes what the product is or what the README promises, stop on that point, ask Emi, and continue with whatever does not depend on his answer.
- **Keep the paperwork small.** The documents are the README and this file. No progress logs, no planning files, no review archives. A fact lives in one file.
- **Sub-agents:** at most two at a time on Emi's machine, where memory is tight. One writer per file. An independent reviewer for anything that touches the core. A sub-agent does not inherit these rules: its brief gives the goal, the files it may touch, what is forbidden, and the proof expected.

## Proving

```sh
python3 -m unittest discover -s tests       # the Python tests
node --test tests/test_something_js.mjs     # the tests of something.js
```

- **Tests use fakes shaped exactly like real data.** A fake Herdr socket, fake session files with invented text. A fixture that does not match the real shape proves nothing.
- **Test servers listen on `127.0.0.1` and take a free port from the system** (port 0), never a fixed one. Stop what you start, and check it.
- **A fresh environment, after each commit.** The suite also runs from a clean clone with an empty home folder, which is what a newcomer has. It catches a file left out of the commit and anything that leans on your own machine:

  ```sh
  tmp=$(mktemp -d) && git clone -q . "$tmp/clone" && mkdir "$tmp/home" &&
    (cd "$tmp/clone" && env -u HERDR_SOCKET_PATH HOME="$tmp/home" python3 -m unittest discover -s tests)
  code=$?; rm -rf "$tmp"; (exit $code)
  ```

- **Other machines.** At each push GitHub runs the suite on macOS and Linux, on the oldest Python the README promises and on a recent one (`.github/workflows/tests.yml`). A red run is fixed before anything else.
- **A virtual machine, before a version is tagged.** The full trial as a newcomer (a machine without Herdr and without any agent, then with them) happens there. Starting one is Emi's decision.
- **Green tests do not replace a trial on real sessions.** A reader is also checked, read-only, against real session files.
- **Session content is private.** Never print it, log it, copy it outside the machine, or paste it in a report, an issue or a commit. Describe shapes, not content.

## Never without Emi

- Push, publish, deploy, install anything, or change a global configuration (Herdr, an agent's settings, the shell).
- Make the repository public, change its settings on GitHub, tag or release a version, rewrite a history that was pushed.
- Listen anywhere other than `127.0.0.1`.
- Send anything to a real agent: no message, no key, no answer. Reading is free; writing is his gesture.
- Start, stop or close a real agent, a real terminal or a virtual machine.
- Read, show or copy a secret (`.env`, keys, tokens).
- Write, change or delete anything outside this repository, except a temporary folder you created yourself.

Ask him once, at the start, whether you may launch something yourself on a local test port to read his real sessions. Until he says yes, he launches it.
