"""Publishable: nothing personal in what the repository publishes. No key, no home folder with a real name, no
e-mail address, no secret file.

Two scans, through `git`: the files that are tracked or about to be, and the commits of the current branch that no
remote holds yet, with their authors. A commit stays in the history even when a later one removes what it added, so
it is scanned before it leaves. Outside a Git clone (a downloaded archive), both are skipped. What no scan can
see: session content copied into a fixture, and an address inside an image or a database. That stays a rule
(AGENTS.md, "Publishable").
"""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDERS = {"example", "me", "you", "name", "user"}       # the home folders an example may name
# The addresses that name nobody: examples, the hosts' no-reply addresses (GitHub signs a merge made on its site
# with one), the user of a clone over SSH.
NOBODY = ("example.com", "example.org", "noreply.github.com", "noreply@github.com", "noreply@anthropic.com",
          "git@github.com")
SECRET_FILES = re.compile(r"(^|/)(\.env(\..*)?|.*\.(pem|key|p12|pfx)|id_(rsa|dsa|ecdsa|ed25519))$")
HOME = re.compile(r"(?:/Users/|/home/|[A-Za-z]:\\Users\\)([A-Za-z0-9._-]+)")
# The same folder inside the name of a session folder, where a harness writes the path with dashes:
# "-Users-example-Projects-bookshop". something shortens the home folder at the start of a path to "~", not this
# one. Only at the start of a name: "at-home-care" is an ordinary word, and so is an option called "--home-dir",
# which is why the Linux form is only looked for right after a path separator.
DASHED_HOME = re.compile(r"(?:(?<=[/\\\"'`])(?:[A-Za-z]-)?--?Users|(?<=[/\\])--?home)-([A-Za-z0-9_]+)")
# What is asked of `git log`: one block per commit, opened by a NUL and its full name, then its author, its
# committer, its message and its changes (--cc: also what a merge adds by itself). The two --no options: the
# person's own Git settings must not add a signature or a colour to what is read.
LOG = ("log", "--cc", "--no-color", "--no-show-signature", "--format=%x00commit %H%n%an <%ae>%n%cn <%ce>%n%B")
# An address starts with a letter or a digit: "+@AGENTS.md", an added line as a commit shows it, is not one.
MAIL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._%+-]*@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")
KEYS = {
    "a private key": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "a model provider's key": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),
    "a GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "an AWS key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "a Google key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}"),
    "a Slack token": re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
}


def findings(text):
    """What must not be published in this text: the kinds found, never the text itself (a report must not repeat
    a secret)."""
    found = {kind for kind, shape in KEYS.items() if shape.search(text)}
    if any(name.lower() not in PLACEHOLDERS for name in HOME.findall(text) + DASHED_HOME.findall(text)):
        found.add("a home folder with a real name")
    if any(not mail.lower().endswith(NOBODY) for mail in MAIL.findall(text)):
        found.add("an e-mail address")
    return sorted(found)


def in_commits(log):
    """What must not be published in the output of `git log` asked with LOG: one "commit <name>: <kind>" per find.
    A NUL inside a change opens no commit: what follows it belongs to the same one, and is never printed."""
    problems = []
    for block in re.split(r"\0(?=commit [0-9a-f]{40,64}\n)", log)[1:]:
        name, author, committer, rest = (block.split("\n", 3) + [""] * 3)[:4]
        name = name[7:17]       # after "commit ", the first ten characters of its name
        # An address is judged whole here, whatever its shape: "name@machine" has no dot and is one all the same.
        if not all(line.rpartition("<")[2].rstrip(">").lower().endswith(NOBODY) for line in (author, committer)):
            problems.append(f"commit {name}: the address of its author or of its committer")
        problems += [f"commit {name}: {kind}" for kind in findings(rest)]
    return problems


def git(*arguments):
    """The output of a `git` command run in the repository, or None: no Git, not a clone, or a refusal."""
    try:
        done = subprocess.run(["git", "-C", str(ROOT), *arguments], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return done.stdout.decode("utf-8", "replace") if done.returncode == 0 else None


class Scanner(unittest.TestCase):
    """The scanner sees each kind, on made-up values cut in two so that this file does not name one whole."""

    def test_each_kind_is_found(self):
        for kind, text in (
                ("a private key", "-----BEGIN OPENSSH " + "PRIVATE KEY-----"),
                ("a model provider's key", "key = sk-" + "a1B2" * 8),
                ("a GitHub token", "ghp_" + "a1B2" * 9),
                ("a GitHub token", "github_pat_" + "a1B2_" * 8),
                ("an AWS key", "AKIA" + "ABCD1234" * 2),
                ("a Google key", "AIza" + "a1B2-c3" * 5),
                ("a Slack token", "xoxb-" + "1234-abcd-5678"),
                ("a home folder with a real name", "/Users/" + "ada/Projects/shop"),
                ("a home folder with a real name", "/home/" + "ada/.config"),
                ("a home folder with a real name", "C:\\Users\\" + "ada\\shop"),
                ("a home folder with a real name", "~/.claude/projects/-Users-" + "ada-Projects-shop/5b2e.jsonl"),
                ("a home folder with a real name", "~/.pi/agent/sessions/--home-" + "ada-code-shop--/5b2e.jsonl"),
                ("a home folder with a real name", '"C--Users-' + 'ada-shop"'),
                ("an e-mail address", "ada@" + "lovelace.dev")):
            with self.subTest(text):
                self.assertEqual(findings(text), [kind])

    def test_what_an_example_may_say_is_not_found(self):
        for text in ("/Users/example/Projects/bookshop", "/home/me/.config", "~/.claude/projects", "ada@example.com",
                     "Co-Authored-By: Claude <noreply@anthropic.com>", "12345+ada@users.noreply.github.com",
                     "git clone git@github.com:example/something.git", "+@AGENTS.md",
                     "~/.claude/projects/-Users-example-Projects-bookshop/5b2e.jsonl", "a stay-at-home-parent",
                     "a { color: var(--home-link-color); }", "run it with --home-dir-override /srv",
                     "-home-made-jam is on the table", 'add_argument("--home-dir")', "GitHub <noreply@github.com>",
                     "context: { tokens: 182000 }", "a risk-assessment of the task", "@media (max-width: 40em)"):
            with self.subTest(text):
                self.assertEqual(findings(text), [])

    def test_a_commit_is_judged_with_its_author(self):
        name = "0123456789abcdef" * 2 + "01234567"
        clean = (f"\0commit {name}\nExample <1+example@users.noreply.github.com>\nGitHub <noreply@github.com>\n"
                 "A title\n\ndiff --git a/note b/note\n+one line\n")
        self.assertEqual(in_commits(clean), [])
        personal = clean.replace("1+example@users.noreply.github.com", "ada@" + "laptop")
        self.assertEqual(in_commits(personal), [f"commit {name[:10]}: the address of its author or of its committer"])
        cut = clean + "+before\0commit " + "sk-" + "a1B2" * 8 + "\n+/Users/" + "ada/shop\n"       # a NUL in a change
        self.assertEqual(in_commits(cut), [f"commit {name[:10]}: a home folder with a real name",
                                           f"commit {name[:10]}: a model provider's key"])
        self.assertEqual(len(in_commits(clean + clean.replace("one line", "/home/" + "ada/notes"))), 1)

    def test_a_secret_file_is_named_by_its_name(self):
        for name in (".env", ".env.local", "deploy/.env", "server.pem", "keys/host.key", "id_ed25519"):
            self.assertTrue(SECRET_FILES.search(name), name)
        for name in ("README.md", "something/guards.py", "page/example.json", "tests/test_main.py", "environment.md"):
            self.assertFalse(SECRET_FILES.search(name), name)


class Repository(unittest.TestCase):
    def test_the_files_hold_nothing_personal(self):
        listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
        if listed is None:
            self.skipTest("not a Git clone")
        problems = []
        for name in filter(None, listed.split("\0")):
            if SECRET_FILES.search(name):
                problems.append(f"{name}: a secret file")
            problems += [f"{name}: {kind}, in its name" for kind in findings(name)]
            try:
                content = (ROOT / name).read_bytes()
            except OSError:         # deleted and not committed yet, or not a regular file
                continue
            kinds = findings(content.decode("utf-8", "replace"))
            if b"\0" in content:    # an image, a font, a database: its bytes take the shape of an address by chance
                kinds = [kind for kind in kinds if kind != "an e-mail address"]
            problems += [f"{name}: {kind}" for kind in kinds]
        self.assertEqual(problems, [])

    def test_the_commits_to_push_hold_nothing_personal(self):
        if git("rev-parse", "--verify", "--quiet", "HEAD") is None or (git("rev-parse", "--show-prefix") or "").strip():
            self.skipTest("not a Git clone of its own, or no commit yet")
        if not git("for-each-ref", "--count=1", "refs/remotes"):
            self.skipTest("no branch of a remote to compare with: nothing says which commits are already published")
        # The commits of the current branch that no remote holds: also those of a branch that was never pushed.
        unpushed = ("HEAD", "--not", "--remotes")
        commits, count = git(*LOG, *unpushed), git("rev-list", "--count", *unpushed)
        self.assertFalse(commits is None or count is None, "the commits to push could not be read: nothing is proven")
        self.assertEqual(len(re.findall(r"\0commit [0-9a-f]{40,64}\n", commits)), int(count), "a commit was not read")
        self.assertEqual(in_commits(commits), [], "in a commit of this branch that no remote holds yet. An address "
                         "of author or committer: give Git a no-reply address (GitHub offers one in its e-mail "
                         "settings), then amend the commit. Anything else: rewrite the commit before pushing; a later "
                         "commit that removes the value leaves it in the history.")


if __name__ == "__main__":
    unittest.main()
