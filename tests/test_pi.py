"""The pi reader, on fake logs with the exact shape of real ones: the one from before pi 1.0.0, taken from real
files, and what pi 1.0.0 documents on top of it. No real text: everything is invented."""
import itertools
import json
import os
import shutil
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import extensions, guards  # noqa: E402
from extensions import _reading as reading     # noqa: E402

pi = extensions.import_file(extensions.FOLDER / "pi.py")

UUID = "019e8aaa-bbbb-7ccc-8ddd-eeeeffff0001"
T0 = datetime(2026, 10, 7, 4, 0, tzinfo=timezone.utc).timestamp()   # time zero of the fake logs
NOW = T0 + 3600
KEYS = {"title", "model", "effort", "context", "cost", "tool", "request", "todos", "goal", "subagents", "activity"}
_numbers = itertools.count(1)
_last = [None]        # the identifier of the last line made: the parent of the next one


# The line factory: each function returns a log line as pi writes it.

def date(t):
    return datetime.fromtimestamp(T0 + t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def ms(t):
    """The date of a message: Unix milliseconds, when that of its line is in ISO."""
    return int((T0 + t) * 1000)


def line(type_, t=0, **fields):
    """A line of the tree: type, id of 8 hex, parentId (the line before), ISO date in UTC. `t`: seconds after T0."""
    ident = fields.pop("id", None) or "%08x" % next(_numbers)
    o = {"type": type_, "id": ident, "parentId": _last[0], "timestamp": date(t), **fields}
    _last[0] = ident
    return json.dumps(o, separators=(",", ":"), ensure_ascii=False)


def header():
    """The first line: outside the tree, without parentId."""
    return json.dumps({"type": "session", "version": 3, "id": UUID, "timestamp": date(0), "cwd": "/tmp/trial"},
                      separators=(",", ":"))


def model(provider="openai-codex", name="gpt-5.5", t=0):
    return line("model_change", t, provider=provider, modelId=name)


def effort(level, t=0):
    return line("thinking_level_change", t, thinkingLevel=level)


def user(content, t=0, string=False, **fields):
    """A typed message: a list of blocks before pi 1.0.0, a string too since then (`string`)."""
    message = {"role": "user", "content": content if string else [text(content)], "timestamp": ms(t)}
    return line("message", t, message=message, **fields)


def usage(tokens=1000, cost=0.25):
    """The usage of a call to the model; `totalTokens` is the sum of the four parts. `tokens` at 0: all is zero."""
    return {"input": 0, "output": min(10, tokens), "cacheRead": max(0, tokens - 10), "cacheWrite": 0,
            "totalTokens": tokens, "cost": {"input": 0, "output": cost, "cacheRead": 0, "cacheWrite": 0, "total": cost}}


def assistant(*blocks, t=0, stop="toolUse", tokens=1000, cost=0.25, provider="openai-codex", name="gpt-5.5", level=None):
    """A reply of the model. `tokens` at 0: a failed reply. `level`: the thinkingLevel written since pi 1.0.0."""
    message = {"role": "assistant", "content": list(blocks), "api": "openai-codex-responses", "provider": provider,
               "model": name, "usage": usage(tokens, cost), "stopReason": stop, "timestamp": ms(t), "responseId": "resp_0"}
    if level:
        message["thinkingLevel"] = level
    return line("message", t, message=message)


def text(content):
    return {"type": "text", "text": content}


def call(ident, name, **arguments):
    return {"type": "toolCall", "id": ident, "name": name, "arguments": arguments}


def result(ident, name, t=0, error=False, **fields):
    message = {"role": "toolResult", "toolCallId": ident, "toolName": name, "content": [text("result")],
               "isError": error, "timestamp": ms(t), **fields}
    return line("message", t, message=message)


def without_tree(l):
    """The same line in the old format: without `id` or `parentId`."""
    return json.dumps({c: v for c, v in json.loads(l).items() if c not in ("id", "parentId")},
                      separators=(",", ":"), ensure_ascii=False)


def numbers(turns):
    """The numbers of the questions that open these turns ("Question 3" → 3)."""
    return [int(turn["text"].split()[1]) for turn in turns]


class Case(unittest.TestCase):
    """A fake pi folder in a temporary folder, in place of the real root."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="something-pi-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        patch = mock.patch.object(pi, "ROOT", self.root)
        patch.start()
        self.addCleanup(patch.stop)
        pi._followed.clear()
        pi._windows.clear()
        _last[0] = None                       # the first line of the tree has no parent
        self.path = self.root / "sessions" / "--tmp-trial--" / ("2026-10-07T04-00-00-000Z_" + UUID + ".jsonl")
        self.session = {"id": UUID, "path": str(self.path)}

    def write(self, *lines, path=None, age=0, head=None):
        """Writes a log (the header, then `lines`), `age` seconds old."""
        path = path or self.path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(l + "\n" for l in (head or [header()]) + list(lines)), encoding="utf-8")
        os.utime(path, (NOW - age, NOW - age))
        return path

    def append(self, *lines, end="\n", age=0):
        with open(self.path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + end)
        os.utime(self.path, (NOW - age, NOW - age))

    def catalog(self, content=None, **providers):
        """A fake models-store.json: catalog(**{"openai-codex": {"gpt-5.5": 272000}}), or a raw content."""
        entries = {p: {"models": [{"id": name, "name": name, "api": "openai-responses", "provider": p, "reasoning": True,
                                   "contextWindow": window, "maxTokens": 32000} for name, window in models.items()],
                       "checkedAt": 1790950820989, "lastModified": 1790859106000, "etag": 'W/"0"'}
                   for p, models in providers.items()}
        path = self.root / "models-store.json"
        path.write_text(json.dumps(entries, indent=2) if content is None else content, encoding="utf-8")
        instant = NOW + next(_numbers)                          # each write of the catalog has its own date
        os.utime(path, (instant, instant))

    def read(self, now=NOW):
        state = pi.read(self.session, now)
        self.assertEqual(set(state), KEYS)
        return state


class Session(Case):
    def herdr(self, kind, value):
        return {"agent": "pi", "agent_session": {"agent": "pi", "kind": kind, "source": "herdr:pi", "value": value}}

    def test_by_path(self):
        self.assertEqual(pi.session(self.herdr("path", str(self.path))), self.session)   # the log does not exist yet

    def test_identifier_from_the_name(self):
        for name, ident in (("2026-10-07T04-00-00-000Z_my_trial", "my_trial"), ("trial", "trial")):
            path = str(self.path.with_name(name + ".jsonl"))
            self.assertEqual(pi.session(self.herdr("path", path)), {"id": ident, "path": path})

    def test_missing(self):
        self.write()
        for agent in (None, "pi", {}, {"agent_session": None}, {"agent_session": "path"}, self.herdr("path", None),
                      self.herdr("path", 12), self.herdr("path", ""), self.herdr("other", str(self.path)),
                      self.herdr(["path"], str(self.path)), self.herdr("id", UUID)):   # `id`: pi started without a log
            self.assertIsNone(pi.session(agent), agent)

    def test_a_file_outside_the_sessions_is_not_a_log(self):
        outside = str(self.root / "sessions" / "x" / ".." / ".." / "elsewhere.jsonl")
        for value in ("/etc/passwd", str(self.root / "models-store.json"), str(self.root / "elsewhere.jsonl"), outside,
                      str(self.path.with_suffix(".json")), "sessions/relative.jsonl", "a\x00b.jsonl"):
            self.assertIsNone(pi.session(self.herdr("path", value)), value)


class Reading(Case):
    def test_log_without_message_everything_is_unknown(self):
        self.write(age=30)
        state = self.read()
        self.assertEqual(state["activity"], guards.iso(NOW - 30))
        self.assertEqual((state["todos"], state["subagents"]), ([], []))      # pi has none
        for key in KEYS - {"activity", "todos", "subagents"}:
            self.assertIsNone(state[key], key)

    def test_missing_log(self):
        with self.assertRaises(OSError):      # pi only writes it at the first message
            self.read()
        self.write()
        self.read()
        self.path.unlink()
        with self.assertRaises(OSError):
            self.read()

    def test_old_shape(self):
        """A log from before pi 1.0.0: contents as lists of blocks, the effort said by its line alone."""
        search = {"id": "r1", "type": "search", "timestamp": ms(13), "queries": []}
        self.write(model(), effort("high"), user("Tidy the workshop", t=10),
                   assistant({"type": "thinking", "thinking": "I am thinking", "thinkingSignature": "x"},
                             call("call_1|fc_1", "bash", command="ls", timeout=10), t=12, tokens=42000, cost=0.25),
                   result("call_1|fc_1", "bash", t=13),
                   line("custom", t=13, customType="web-search-results", data=search),
                   assistant(text("It is tidy"), t=20, stop="stop", tokens=43000, cost=0.5), age=30)
        self.assertEqual(self.read(), {
            "title": None, "model": "openai-codex/gpt-5.5", "effort": "high",
            "context": {"tokens": 43000, "window": None, "percent": None}, "cost": 0.75, "tool": None,
            "request": None, "todos": [], "goal": None, "subagents": [], "activity": guards.iso(NOW - 30)})

    def test_shape_1_0_0(self):
        """What pi 1.0.0 documents on top of it: system message, content as a string, effort on the reply, session
        name, `usage` lines, usage of a tool and of a summary."""
        system = {"role": "system", "content": "", "sections": {"preamble": "You are an assistant", "cwd": "/tmp/trial"},
                  "toolsAdded": [{"name": "read", "description": "Read", "parameters": {}}], "timestamp": ms(0)}
        self.write(model("anthropic", "claude-opus-5-5"), effort("high"), line("message", message=system),
                   user("Tidy the workshop", t=10, string=True),
                   assistant(call("toolu_1", "read", path="plan.md"), t=12, tokens=42000, cost=0.25, level="medium",
                             provider="anthropic", name="claude-opus-5-5"),
                   line("usage", t=12, kind="cache_warm", provider="anthropic", model="claude-opus-5-5",
                        usage=usage(50000, 0.125)),
                   line("session_info", t=12, name="  Tidying the workshop "),
                   line("label", t=12, targetId="00000001", label="mark"),
                   line("context_edit", t=12, targetId="00000001", replacement=None),
                   line("custom_message", t=12, customType="trial", content="Injected context", display=True),
                   line("branch_summary", t=12, fromId="00000001", summary="Summary", usage=usage(200, 0.0625)))
        expected = {"title": "Tidying the workshop", "model": "anthropic/claude-opus-5-5", "effort": "medium",
                    "context": {"tokens": 42000, "window": None, "percent": None}, "cost": 0.4375,
                    "tool": {"name": "read", "since": guards.iso(T0 + 12)}, "request": None, "todos": [], "goal": None,
                    "subagents": [], "activity": guards.iso(NOW)}
        self.assertEqual(self.read(), expected)
        self.append(result("toolu_1", "read", t=13, usage=usage(300, 0.0625)))
        self.assertEqual(self.read(), dict(expected, tool=None, cost=0.5))

    def test_title_from_session_info(self):
        self.write(user("Hello"))
        self.assertIsNone(self.read()["title"])
        self.append(line("session_info", name="First name"), line("session_info", name="Second name"))
        self.assertEqual(self.read()["title"], "Second name")
        self.append(line("session_info", name="  "))
        self.assertIsNone(self.read()["title"])                 # an empty name removes the title

    def test_model_the_last_to_speak(self):
        self.write(model("openai-codex", "gpt-5.5"))
        self.assertEqual(self.read()["model"], "openai-codex/gpt-5.5")    # holds as soon as it appears, without a reply
        self.append(assistant(text("One"), provider="opencode-go", name="kimi-k3"))
        self.assertEqual(self.read()["model"], "opencode-go/kimi-k3")     # a virtual model: the one that really answered
        self.append(model("ollama", "glm-5.2:cloud"))
        self.assertEqual(self.read()["model"], "ollama/glm-5.2:cloud")

    def test_effort_changes_in_the_middle_of_the_log(self):
        self.write(effort("low"), assistant(text("One")))
        self.assertEqual(self.read()["effort"], "low")
        self.append(effort("xhigh"), *[assistant(text("Reply " + str(i))) for i in range(300)])
        self.assertEqual(self.read()["effort"], "xhigh")        # the change is far from the end, it counts all the same
        self.append(assistant(text("Again")))
        self.assertEqual(self.read()["effort"], "xhigh")        # the log grows without mentioning it: it stays remembered
        self.append(assistant(text("No thinking"), level="off"))
        self.assertEqual(self.read()["effort"], "off")          # pi 1.0.0: the level asked for this reply
        self.append(effort("medium"))
        self.assertEqual(self.read()["effort"], "medium")

    def test_context_from_the_usage_of_the_last_reply(self):
        self.write(assistant(text("One"), tokens=1000), assistant(text("Two"), tokens=42000))
        self.assertEqual(self.read()["context"], {"tokens": 42000, "window": None, "percent": None})

    def test_context_ignores_a_zero_usage(self):
        self.write(assistant(text("One"), tokens=42000), assistant(stop="aborted", tokens=0, cost=0),
                   assistant(stop="error", tokens=0, cost=0))
        self.assertEqual(self.read()["context"]["tokens"], 42000)
        self.append(assistant(text("Two"), stop="stop", tokens=0, cost=0))      # a provider that does not count
        self.assertEqual(self.read()["context"]["tokens"], 42000)
        self.append(assistant(text("Three"), stop="error", tokens=90000))       # a failed reply measures nothing
        self.assertEqual(self.read()["context"]["tokens"], 42000)

    def test_context_unknown_after_compaction(self):
        self.write(assistant(text("One"), tokens=250000, cost=0.25))
        self.assertEqual(self.read()["context"]["tokens"], 250000)
        self.append(line("compaction", summary="Summary", firstKeptEntryId="00000001", tokensBefore=250000,
                         usage=usage(900, 0.125)))
        state = self.read()
        self.assertEqual((state["context"], state["cost"]), (None, 0.375))   # the summary cost money, it measures nothing
        self.append(assistant(text("Two"), tokens=30000, cost=0))
        self.assertEqual(self.read()["context"]["tokens"], 30000)

    def test_percentage_when_the_window_is_known(self):
        self.catalog(**{"openai-codex": {"gpt-5.5": 272000}, "opencode-go": {"gpt-5.5": 1000000}})
        self.write(assistant(text("One"), tokens=68000))
        self.assertEqual(self.read()["context"], {"tokens": 68000, "window": 272000, "percent": 25})
        self.append(assistant(text("Two"), tokens=500000, provider="opencode-go"))   # other provider, other window
        self.assertEqual(self.read()["context"], {"tokens": 500000, "window": 1000000, "percent": 50})
        self.append(assistant(text("Three"), tokens=300000))
        self.assertEqual(self.read()["context"]["percent"], 100)   # never more than 100

    def test_no_percentage_without_a_window(self):
        self.write(assistant(text("One"), tokens=250000))
        expected = {"tokens": 250000, "window": None, "percent": None}
        self.assertEqual(self.read()["context"], expected)                       # no catalog
        self.catalog(**{"openai-codex": {"other-model": 1000000, "gpt-5.5": None}, "ollama": {"gpt-5.5": 9}})
        self.assertEqual(self.read()["context"], expected)                       # model missing, or null window
        for unreadable in ('{"openai-codex":{"models":[', "[1]", "\x00",
                           '{"openai-codex":{"models":"no"},"a":[1],"b":{"models":[1,{"id":3,"contextWindow":"big"}]}}',
                           '{"openai-codex":{"models":[{"id":"gpt-5.5","contextWindow":true},{"id":"gpt-5.5"}]}}'):
            self.catalog(unreadable)
            self.assertEqual(self.read()["context"], expected, unreadable)

    def test_the_catalog_is_read_again_when_it_changes(self):
        self.write(assistant(text("One"), tokens=68000))
        self.catalog(**{"openai-codex": {"gpt-5.5": 272000}})
        self.assertEqual(self.read()["context"]["percent"], 25)
        self.catalog(**{"openai-codex": {"gpt-5.5": 136000, "gpt-5.4-mini": 272000}})
        self.assertEqual(self.read()["context"]["percent"], 50)

    def test_cost(self):
        self.write(user("Hello"))
        self.assertIsNone(self.read()["cost"])                  # no cost read: unknown, not zero
        self.append(assistant(stop="error", tokens=0, cost=0), assistant(text("Free"), cost=0))
        self.assertIsNone(self.read()["cost"])                  # a zero cost is doubtful: free, or price not known
        self.append(assistant(text("One"), cost=0.25), assistant(text("Two"), cost=0.5))
        self.assertEqual(self.read()["cost"], 0.75)

    def test_cost_rounded(self):
        self.write(assistant(text("One"), cost=0.1), assistant(text("Two"), cost=0.2))
        self.assertEqual(self.read()["cost"], 0.3)              # not 0.30000000000000004

    def test_tool_running_then_finished(self):
        self.write(user("List", t=1), assistant(call("call_1", "bash", command="ls"), t=5))
        self.assertEqual(self.read()["tool"], {"name": "bash", "since": guards.iso(T0 + 5)})
        self.append(result("call_1", "bash", t=9))
        self.assertIsNone(self.read()["tool"])

    def test_tools_of_one_reply(self):
        self.write(assistant(call("call_1", "read", path="a"), call("call_2", "grep", pattern="b")))
        self.assertEqual(self.read()["tool"]["name"], "read")   # the first call left without a result
        self.append(result("call_1", "read", error=True))
        self.assertEqual(self.read()["tool"]["name"], "grep")
        self.append(result("call_2", "grep"))
        self.assertIsNone(self.read()["tool"])

    def test_a_failed_reply_starts_no_tool(self):
        self.write(assistant(call("call_1", "bash", command="ls"), stop="error", tokens=0, cost=0))
        self.assertIsNone(self.read()["tool"])
        self.append(assistant(call("call_2", "bash", command="ls"), stop="aborted", tokens=0, cost=0))
        self.assertIsNone(self.read()["tool"])

    def test_a_new_message_closes_the_tools(self):
        self.write(assistant(call("call_1", "bash", command="make")))     # pi stopped in the middle of a tool…
        self.assertEqual(self.read()["tool"]["name"], "bash")
        self.append(user("Resume"))                                       # …then resumed: the call will not come back
        self.assertIsNone(self.read()["tool"])

    def test_log_that_grows(self):
        self.write(model(), assistant(text("One"), cost=0.25), age=60)
        self.assertEqual(self.read()["cost"], 0.25)
        self.assertEqual(self.read()["cost"], 0.25)             # reading again without a change counts nothing again
        rest = assistant(call("call_1", "bash", command="ls"), cost=0.5, tokens=5000)
        self.append(rest[:40], end="", age=30)                  # a line being written
        self.assertEqual(self.read()["cost"], 0.25)
        self.append(rest[40:], model("opencode-go", "kimi-k3"))
        state = self.read()
        self.assertEqual((state["cost"], state["model"], state["tool"]["name"], state["context"]["tokens"]),
                         (0.75, "opencode-go/kimi-k3", "bash", 5000))
        self.assertEqual(state["activity"], guards.iso(NOW))

    def test_log_that_shrinks(self):
        self.write(assistant(text("One"), cost=0.25), assistant(call("call_1", "bash", command="ls"), cost=0.25))
        self.assertEqual(self.read()["cost"], 0.5)
        self.write(assistant(text("Other"), cost=0.125))
        state = self.read()
        self.assertEqual((state["cost"], state["tool"]), (0.125, None))   # the read started again from zero

    def test_log_replaced_by_another_file(self):
        self.write(assistant(call("call_1", "bash", command="ls"), cost=0.25))
        before = (self.read()["cost"], os.stat(self.path).st_size)
        _last[0] = None                                         # another log: another tree
        other = self.write(assistant(call("call_2", "read", command="ls"), cost=0.75),
                           path=self.path.with_name("other.jsonl"))
        os.replace(other, self.path)                            # same size, same date: only the inode gives it away
        state = self.read()
        self.assertEqual(before, (0.25, os.stat(self.path).st_size))
        self.assertEqual((state["cost"], state["tool"]["name"]), (0.75, "read"))


HOSTILE = [
    '{"type":"message","id":"0000000a","message":{"role":"assistant","content":[{"type":"te',    # cut JSON
    "", "null", "[]", '"text"', "12", "{}", "\x00\x01\x02", "[" * 100000,
    '{"type":["message"],"timestamp":true}',
    '{"type":"message"}',
    '{"type":"message","message":"not an object","timestamp":{}}',
    '{"type":"message","id":7,"message":{"role":"user","content":"without identifier"}}',
    '{"type":"message","id":"0000000b","message":{"role":"user","content":[1,null,{"type":"text","text":5}]}}',
    '{"type":"message","id":"0000000c","message":{"role":"user","content":{"type":"text","text":"an object"}}}',
    '{"type":"message","id":"0000000d","message":{"role":["user"],"content":"a role as a list"}}',
    '{"type":"message","message":{"role":"assistant","content":"x","usage":[1],"provider":3,"model":null,"thinkingLevel":7}}',
    '{"type":"message","message":{"role":"assistant","content":[1,null,{"type":"toolCall","id":[1],"name":"bash"},'
    '{"type":"toolCall","id":"a","name":{"x":1},"arguments":"no"}],"usage":{"totalTokens":"many",'
    '"cost":{"total":"expensive"}},"provider":"anthropic","stopReason":["stop"]}}',
    '{"type":"message","message":{"role":"assistant","usage":{"totalTokens":NaN,"cost":{"total":Infinity}}}}',
    '{"type":"message","message":{"role":"assistant","content":[{"type":"text","id":"b","name":"bash","text":7}]}}',
    '{"type":"message","message":{"role":"assistant","usage":{"totalTokens":true,"cost":true}}}',
    '{"type":"message","message":{"role":"assistant","usage":{"totalTokens":-5,"cost":{"total":-1}}}}',
    '{"type":"message","message":{"role":"toolResult","toolCallId":{"a":1},"toolName":["bash"],"usage":"no"}}',
    '{"type":"message","message":{"role":"system","content":"","sections":[1],"toolsAdded":"no"}}',
    '{"type":"message","message":{"role":"bashExecution","command":7,"output":null}}',
    '{"type":"usage","usage":[1]}',
    '{"type":"usage","kind":3,"usage":{"totalTokens":900,"cost":{"total":null}}}',
    '{"type":"model_change","provider":5,"modelId":["x"]}',
    '{"type":"model_change","provider":"openai-codex"}',
    '{"type":"thinking_level_change","thinkingLevel":["high"]}',
    '{"type":"session_info","name":{"a":1}}',
    '{"type":"session_info"}',
    '{"type":"compaction","tokensBefore":"x","usage":7}',
    '{"type":"session","timestamp":{"a":1},"id":4}',
    '{"type":"custom","customType":{"a":1},"data":null}',
    '{"type":"custom_message","content":[1],"display":"yes"}',
    '{"type":"message","id":["a"],"parentId":{"b":1},"message":{"role":"assistant","content":"an identifier as a list"}}',
    '{"type":"message","id":"0000000e","parentId":"0000000e","message":{"role":"assistant","content":"its own parent"}}',
]


class Robustness(Case):
    def test_hostile_lines(self):
        self.write(*HOSTILE, head=["not a header"], age=10)
        state = self.read()
        self.assertEqual(state["activity"], guards.iso(NOW - 10))
        self.assertEqual((state["todos"], state["subagents"]), ([], []))
        for key in KEYS - {"activity", "todos", "subagents"}:
            self.assertIsNone(state[key], key)
        self.assertEqual(pi.turns(self.session), {"turns": [], "older": False, "before": None})

    def test_a_hostile_line_erases_what_it_makes_unreadable(self):
        self.write(model(), effort("high"), line("session_info", name="Trial"))
        self.assertEqual([self.read()[k] for k in ("model", "effort", "title")], ["openai-codex/gpt-5.5", "high", "Trial"])
        self.append(*HOSTILE)                                   # an unreadable change: the old value would be false
        self.assertEqual([self.read()[k] for k in ("model", "effort", "title")], [None, None, None])

    def test_a_hostile_line_does_not_hide_the_good_ones(self):
        good = [model(), user("Hello", id="0000aaaa"),
                assistant(text("Hi"), stop="stop", tokens=3000, cost=0.5)]
        self.write(*[l for one in good for l in HOSTILE[:9] + [one]])
        state = self.read()
        self.assertEqual((state["model"], state["cost"], state["context"]["tokens"]), ("openai-codex/gpt-5.5", 0.5, 3000))
        self.assertEqual([t["text"] for t in pi.turns(self.session)["turns"]], ["Hello"])

    def test_a_hostile_tree_is_read_all_the_same(self):
        self.write(user("Question 1", id="aaaa0001", parentId="aaaa0002"),              # two lines, each one the
                   user("Question 2", id="aaaa0002", parentId="aaaa0001"))              # parent of the other
        self.assertEqual(numbers(pi.turns(self.session)["turns"]), [1, 2])
        self.append(user("Question 3", id="aaaa0003", parentId=["aaaa0002"]))           # an unreadable parent: a root
        self.assertEqual(numbers(pi.turns(self.session)["turns"]), [3])
        self.append(user("Question 4", id="aaaa0004", parentId="ffffffff"))             # a parent nothing carries
        self.assertEqual(numbers(pi.turns(self.session)["turns"]), [4])


class Turns(Case):
    def conversation(self, n, start=1):
        """n turns, from "Question `start`" to the next ones: the identifier aaaa000i, one final reply each."""
        return [l for i in range(start, start + n) for l in (user("Question %d" % i, t=10 * i, id="aaaa%04x" % i),
                                                             assistant(text("Reply %d" % i), t=10 * i + 5, stop="stop"))]

    def branches(self, trunk, left, current):
        """A log with two branches, in two pieces: `trunk` turns then `left` turns; then, as after going back with
        /tree, `current` turns whose first one has the trunk's last reply as its parent. On real logs, a fork has
        this shape: several `user` messages of the same parent. The questions are numbered in the order of the
        file."""
        first = self.conversation(trunk)
        back = _last[0]                                         # the trunk's last reply
        first += self.conversation(left, start=trunk + 1)
        _last[0] = back                                         # pi starts again from this line
        return first, self.conversation(current, start=trunk + left + 1)

    def test_splitting(self):
        self.write(
            model(), effort("high"),
            assistant(text("Reply without a question"), t=1),    # before any message: belongs to no turn
            user("Tidy the workshop", t=10, id="0000aaaa"),
            assistant({"type": "thinking", "thinking": "I am thinking", "thinkingSignature": "x"}, text("I am looking"),
                      call("call_1", "read", path="/tmp/trial/plan.md", limit=20),
                      call("call_2", "bash", command="ls /tmp/trial", timeout=10),
                      call("call_3", "grep", pattern="workshop", path="/tmp/trial"),
                      call("call_4", "fetch_content", url="https://example.test/plan"),
                      call("call_5", "web_search", queries=["workshop"], numResults=3), t=12),
            result("call_1", "read", t=13),
            line("custom_message", t=14, customType="trial", content="Injected context", display=True),
            line("message", t=15, message={"role": "bashExecution", "command": "ls", "output": "plan.md", "exitCode": 0,
                                           "cancelled": False, "truncated": False, "timestamp": ms(15)}),
            line("branch_summary", t=15, fromId="0000aaaa", summary="Summary of another branch"),
            user("   ", t=16),                                   # an empty message opens no turn
            assistant(text("It is tidy"), t=20, stop="stop"),
            user("And next?", t=30, id="0000bbbb", string=True),                 # pi 1.0.0: the content is a string
            assistant(text("I am stopping"), t=32, stop="aborted", tokens=0, cost=0))
        self.assertEqual(pi.turns(self.session), {"older": False, "before": None, "turns": [
            {"id": "0000aaaa", "t": guards.iso(T0 + 10), "from": "user", "text": "Tidy the workshop",
             "replies": [{"t": guards.iso(T0 + 12), "text": "I am looking"},
                         {"t": guards.iso(T0 + 20), "text": "It is tidy"}],
             "tools": [{"name": "read", "target": "/tmp/trial/plan.md"}, {"name": "bash", "target": "ls /tmp/trial"},
                       {"name": "grep", "target": "workshop"},
                       {"name": "fetch_content", "target": "https://example.test/plan"},
                       {"name": "web_search", "target": None}],
             "end": guards.iso(T0 + 20)},
            {"id": "0000bbbb", "t": guards.iso(T0 + 30), "from": "user", "text": "And next?",
             "replies": [{"t": guards.iso(T0 + 32), "text": "I am stopping"}], "tools": [], "end": None}]})

    def test_clipping(self):
        self.write(user("m" * 5000), assistant(text("r" * 9000), call("call_1", "bash", command="c" * 300)))
        (turn,) = pi.turns(self.session)["turns"]
        lengths = (len(turn["text"]), len(turn["replies"][0]["text"]), len(turn["tools"][0]["target"]))
        self.assertEqual(lengths, (4000, 8000, 160))
        self.assertTrue(turn["text"].endswith("…"))

    def test_paging_by_before(self):
        self.write(*self.conversation(5))
        page = pi.turns(self.session, limit=2)
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 4", "Question 5"], True, "aaaa0004"))
        page = pi.turns(self.session, limit=2, before=page["before"])
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 2", "Question 3"], True, "aaaa0002"))
        page = pi.turns(self.session, limit=2, before=page["before"])
        self.assertEqual(page["turns"][0]["replies"][0]["text"], "Reply 1")
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 1"], False, None))
        self.assertEqual(pi.turns(self.session, limit=2, before="aaaa0001")["turns"], [])
        self.assertEqual(len(pi.turns(self.session)["turns"]), 5)

    def test_unknown_before(self):
        self.write(*self.conversation(3))
        with self.assertRaises(LookupError):
            pi.turns(self.session, before="ffffffff")

    def test_the_end_of_the_log_grows_as_long_as_it_is_not_enough(self):
        self.write(*self.conversation(40))
        whole = pi.turns(self.session, limit=50)["turns"]
        with mock.patch.object(reading, "TAIL", 900):             # a tail that does not hold two turns
            for limit in range(1, 12):    # even when the tail holds just `limit` turns, older ones remain
                page = pi.turns(self.session, limit=limit)
                self.assertEqual((page["turns"], page["older"], page["before"]),
                                 (whole[-limit:], True, whole[-limit]["id"]))
            page = pi.turns(self.session, limit=4, before="aaaa000a")
            self.assertEqual((page["turns"], page["older"], page["before"]), (whole[5:9], True, "aaaa0006"))
            self.assertEqual(pi.turns(self.session, limit=50)["turns"], whole)
            with self.assertRaises(LookupError):
                pi.turns(self.session, before="ffffffff")

    def test_older_tells_the_truth_when_the_end_read_holds_all_the_turns(self):
        conversation = self.conversation(3)
        self.write(*[model() for _ in range(40)], *conversation)          # a long start without any turn
        end = sum(len(l.encode("utf-8")) + 1 for l in conversation) + 20
        with mock.patch.object(reading, "TAIL", end):                     # the tail holds just the three turns
            page = pi.turns(self.session, limit=3)
        self.assertEqual(([t["text"] for t in page["turns"]], page["older"], page["before"]),
                         (["Question 1", "Question 2", "Question 3"], False, None))

    def test_the_end_read_is_bounded(self):
        self.write(*self.conversation(40))
        whole = pi.turns(self.session, limit=50)["turns"]
        with mock.patch.object(reading, "TAIL", 900), mock.patch.object(reading, "CONVERSATION_MAX", 9000):
            with mock.patch.object(reading, "tail_lines", wraps=reading.tail_lines) as tail:
                page = pi.turns(self.session, limit=50)
            self.assertEqual([a.args[1] for a in tail.call_args_list], [900, 3600, 9000])   # never the whole log
            n = len(page["turns"])
            self.assertTrue(0 < n < 40, n)
            self.assertEqual((page["turns"], page["older"]), (whole[-n:], True))
            self.assertEqual(page["before"], whole[-n]["id"])
            # at the edge of the end read: nothing more to return, but the log is longer than it
            self.assertEqual(pi.turns(self.session, before=page["before"]),
                             {"turns": [], "older": True, "before": None})
            with self.assertRaises(LookupError):
                pi.turns(self.session, before="aaaa0001")
        self.assertEqual(pi.turns(self.session, limit=2, before="aaaa0002")["turns"], whole[:1])

    def test_only_the_current_branch_is_returned(self):
        head = [model(), effort("high")]
        origin = _last[0]                                                          # the line before the first message
        first, rest = self.branches(trunk=2, left=2, current=2)
        self.write(*head, *first)
        self.assertEqual(numbers(pi.turns(self.session)["turns"]), [1, 2, 3, 4])   # no branch yet: everything
        self.append(*rest)                                                         # going back after turn 2
        page = pi.turns(self.session)
        self.assertEqual(numbers(page["turns"]), [1, 2, 5, 6])                     # neither 3 nor 4, and in order
        self.assertEqual([r["text"] for turn in page["turns"] for r in turn["replies"]],
                         ["Reply 1", "Reply 2", "Reply 5", "Reply 6"])
        self.assertEqual((page["older"], page["before"]), (False, None))
        _last[0] = origin                                                          # going back before the first message
        self.append(*self.conversation(1, start=7))
        self.assertEqual(numbers(pi.turns(self.session)["turns"]), [7])

    def test_a_line_without_identifier_is_still_read(self):
        """The old format, without `id` or `parentId`: nothing in it says the branch, the line is kept."""
        question = user("Question 1", t=10, id="aaaa0001")
        replies = [without_tree(assistant(text("I am looking"), call("call_1", "bash", command="ls"), t=12)),
                   without_tree(assistant(text("It is done"), t=20, stop="stop"))]
        self.write(question, *replies)
        (turn,) = pi.turns(self.session)["turns"]
        self.assertEqual(([r["text"] for r in turn["replies"]], turn["tools"], turn["end"]),
                         (["I am looking", "It is done"], [{"name": "bash", "target": "ls"}], guards.iso(T0 + 20)))
        # A log where nothing carries an `id`: as before, no turn (it would have no cursor), and nothing raises.
        self.write(without_tree(question), *replies)
        self.assertEqual(pi.turns(self.session), {"turns": [], "older": False, "before": None})
        self.assertEqual(self.read()["cost"], 0.5)

    def test_paging_by_before_on_a_log_with_branches(self):
        first, rest = self.branches(trunk=3, left=4, current=3)           # the current branch: 1 2 3, then 8 9 10
        self.write(*first, *rest)
        page = pi.turns(self.session, limit=2)
        self.assertEqual((numbers(page["turns"]), page["older"], page["before"]), ([9, 10], True, "aaaa0009"))
        page = pi.turns(self.session, limit=2, before=page["before"])     # over the branch that was left
        self.assertEqual((numbers(page["turns"]), page["older"], page["before"]), ([3, 8], True, "aaaa0003"))
        page = pi.turns(self.session, limit=2, before=page["before"])
        self.assertEqual((numbers(page["turns"]), page["older"], page["before"]), ([1, 2], False, None))
        with self.assertRaises(LookupError):                              # a turn that was left is not a cursor
            pi.turns(self.session, before="aaaa0005")

    def test_the_branch_stops_at_the_edge_of_the_end_read(self):
        first, rest = self.branches(trunk=10, left=15, current=15)
        self.write(*first, *rest)
        whole = pi.turns(self.session, limit=50)["turns"]
        self.assertEqual(numbers(whole), list(range(1, 11)) + list(range(26, 41)))
        with mock.patch.object(reading, "TAIL", 900):             # a tail that does not hold two turns
            for limit in range(1, 25):    # the end read stops in the current branch, in the one left, in the trunk
                page = pi.turns(self.session, limit=limit)
                self.assertEqual((page["turns"], page["older"], page["before"]),
                                 (whole[-limit:], True, whole[-limit]["id"]))
            page = pi.turns(self.session, limit=4, before="aaaa001a")     # before the first turn after going back
            self.assertEqual((page["turns"], page["older"], page["before"]), (whole[6:10], True, "aaaa0007"))
            self.assertEqual(pi.turns(self.session, limit=50)["turns"], whole)

    def test_missing_log(self):
        with self.assertRaises(OSError):
            pi.turns(self.session)


if __name__ == "__main__":
    unittest.main()
