---
name: something
description: "Set up and use something, a small local server that shows the coding agents of a Herdr session on an HTML page. Use when the user asks to install, start or try something, to see what their agents are doing on a page, or to build a page on it."
---

# something

something is a small local server that links [Herdr](https://github.com/herdrdev/herdr), the terminal workspace coding agents run in, to an HTML page: who is working, who is waiting for the person, on which model, with which todos, and what was said. Its README is the contract: <https://github.com/emiwltz/something#readme>. This file is the way in: how to set something up for a person, show it to them, and use it.

Talk to the person in their language, in plain words: they may not be a developer.

## Three rules

- **Say the whole plan first, and get one yes.** Before you touch anything, tell the person in a few lines what you are about to do: check Python, Git and Herdr; install Herdr if it is missing; clone something where they keep their projects; start it and open its page in their browser. Give the two addresses, <https://github.com/herdrdev/herdr> and <https://github.com/emiwltz/something>, so that they can look at what is about to land on their machine. Ask once whether that suits them. After their yes, do not ask again at each step: do it, and say what you do. Install nothing that was not in that plan.
- **Never write to an agent on your own.** something can type a message into the pane of another agent. Do it only when the person asks for that message.
- **Keep it local.** something listens on `127.0.0.1` and reads private sessions. No tunnel, no other address, and nothing of what the page shows leaves the machine.

## Set it up

Do these in order, and tell the person in one line what each step found.

1. **Python and Git.** `python3 --version` must say 3.9 or more, and `git --version` must answer. Otherwise stop and say so: installing them was not in the plan, and it is the person's decision.
2. **Herdr.** `command -v herdr && herdr --version` (something is developed against Herdr 0.9.3). If it is missing, install it as you announced, and say that you do: follow the "install" section of Herdr's own README (today: `brew install herdr` where Homebrew is there, otherwise `curl -fsSL https://herdr.dev/install.sh | sh`). If the installation fails, say what it answered and go on: the example of step 4 works without Herdr.
3. **something.** Clone it where the person keeps their projects (ask if you do not know): `git clone https://github.com/emiwltz/something.git`. Every command below runs from the cloned folder, the one that holds `README.md`: from anywhere else Python answers "No module named something". If a folder named `something` is already there, check that it is this project (`git -C <folder> remote get-url origin`), then `git -C <folder> pull --ff-only`; if Git refuses, stop and tell the person. Nothing else to install or to build. The folder also holds `AGENTS.md`, the rules for people who change something: you are setting it up, not changing it, and this file is your guide.
4. **Show the example.** `python3 -m something --example` runs until it is stopped: do not wait for it to end. Start it in a pane of its own or in the background (see "Where to run it") with its output kept in a file, then wait for the line `something: http://127.0.0.1:8780/ (example data)`, or for the process to exit. If it exits, read its sentence: when the port is taken, perhaps by a something that already runs for real, start the example on another one, for instance `--port 8790`. Open the address **the process printed** in a tab of the person's browser (`open` on macOS, `xdg-open` on Linux); if you cannot open a browser, give them the address. Before you say that nothing on the page is real, check it: `curl -s <address>api/state` must hold `"example": true`. Then say what they are looking at (next section).
5. **Then the real one.** Stop the example: Ctrl+C in its terminal, or `kill <its process number>` if it runs in the background, then check that its port is free. A Herdr session must be running, with the person's agents in its panes: `herdr` starts one. Then `python3 -m something`, and the address it prints. If the page says "Herdr does not answer", no Herdr session is running or its socket is elsewhere: the README's "When it does not work" says what to do.

**Where to run it.** something should keep a terminal of its own, in view: it says there when Herdr can no longer be read. If you are inside Herdr (`test "${HERDR_ENV:-}" = 1`), tell the person that you are about to open a pane next to yours, then run something there: `herdr --skill` prints how (`herdr pane split`, then `herdr pane run`). Otherwise, for the example, the background of your own shell is enough: keep its process number and stop it yourself when you are done, because it can outlive your session. For the real one, give the person the command to run in a terminal of theirs.

## What to say when the page opens

Short, in your own words:

- Each agent of the Herdr session is on the page with its state: working, blocked, done or idle, and unknown when Herdr does not say. "blocked" means it is waiting for them; the count above the agents says those first.
- For the harnesses something has a reader for (Claude Code, Codex, OMP, OpenCode, pi), the page also shows the model, the context, the todos, the tool in progress, the question asked and the conversation. What something cannot read is written "unknown": it never guesses.
- "Open its conversation" shows the last turns, and the field under them writes to that agent.
- This is the blank page: everything, without design, in English. It is one file, `page/index.html`, made to be copied and rebuilt. Offer to build theirs.
- In example mode nothing is real: six made-up agents, and no message is sent. A few lines look like failures (an extension "not loaded", a "log not read", an agent in an unknown state): they are part of the example, to show how something says what goes wrong.

## Use it

- **What is running, without a page.** `python3 -m something --once` prints the state as JSON and exits (with 1 if Herdr could not be read). The keys are in the README, "The state". A value that could not be read is `null`: say "unknown", never zero and never "none".
- **Build a page.** Copy `page/index.html` to `page/<name>.html` and keep what serves the person: it is then served at `http://127.0.0.1:8780/<name>.html`. A page uses `Something.watch`, `Something.onEvent`, `Something.conversation` and `Something.send`, from `/something.js` (README, "Plug in a page"). No dependency, no build step. What an agent wrote goes in with `textContent`, never as HTML. Build against `--example`: it covers the cases without any agent running.
- **Read another harness.** An extension is one file in `extensions/` (README, "Writing an extension").

## When it does not work

Read the sentence something gives, on the page, in its terminal or in `error`, before trying anything: it says what happened. The README's "When it does not work" lists each failure with what to do.
