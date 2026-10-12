"""The skill handed to a coding agent, `skills/something/SKILL.md`, says nothing the project does not do.

The skill repeats a few facts of the README and of the entry point (an address, options, section names) so that
an agent can act without reading everything. This test fails when one of them drifts.
"""
import contextlib
import io
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import something.__main__ as entry      # noqa: E402

SKILL = (ROOT / "skills" / "something" / "SKILL.md").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")


class Skill(unittest.TestCase):
    def test_it_declares_its_name_and_when_to_use_it(self):
        head = re.match(r'---\nname: ([a-z][a-z0-9-]*)\ndescription: "([^"\n]+)"\n---\n', SKILL)
        self.assertIsNotNone(head, "a name in lower case and a description on one line, between two --- lines")
        self.assertEqual(head.group(1), "something", "the name of its folder")
        self.assertLessEqual(len(head.group(2)), 1024)

    def test_each_option_it_gives_exists_and_the_port_is_the_default_one(self):
        said = io.StringIO()
        with contextlib.redirect_stdout(said), self.assertRaises(SystemExit):
            entry.main(["--help"])
        given = set(re.findall(r"`[^`\n]*(--[a-z-]+)[^`\n]*`", SKILL)) - {"--version", "--ff-only", "--skill"}
        self.assertEqual(given, {"--example", "--once", "--port"})
        for option in given:
            self.assertIn(option, said.getvalue())
        self.assertIn("8780 by default", said.getvalue())
        self.assertEqual(set(re.findall(r"http://127\.0\.0\.1:(\d+)/", SKILL)), {"8780"})

    def test_it_points_at_what_the_readme_and_the_page_really_hold(self):
        clone = "git clone https://github.com/emiwltz/something.git"
        self.assertIn(clone, SKILL)
        self.assertIn(clone, README)
        for section in re.findall(r'README(?:\'s|,) "([^"]+)"', SKILL):
            self.assertIn(f"\n## {section}\n", README, section)
        tools = (ROOT / "page" / "something.js").read_text(encoding="utf-8")
        for tool in re.findall(r"`Something\.(\w+)`", SKILL):
            self.assertRegex(tools, rf"\b{tool}\b", tool)
        self.assertTrue((ROOT / "page" / "index.html").is_file())
        self.assertIn("skills/something/SKILL.md", README, "the README says where the skill is")


if __name__ == "__main__":
    unittest.main()
