// The tests of page/something.js, without a browser or a server: a fake `fetch` and a fake `EventSource` are set on
// globalThis, then the file is loaded afresh for each test. At the end, those of the blank page: its script
// runs on a fake document and a fake Something; and that of page/example.json.
// Run: node --test tests/test_something_js.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { beforeEach, test } from "node:test";

const require = createRequire(import.meta.url);
const PATH = require.resolve("../page/something.js");

// The fake stream: the test pushes a state or breaks the connection by hand.
class FakeStream {
  static opened = [];
  constructor(url) {
    this.url = url;
    this.readyState = 0;
    this.listeners = {};
    FakeStream.opened.push(this);
  }
  addEventListener(kind, fn) {
    this.listeners[kind] = fn;
  }
  close() {
    this.readyState = 2;
  }
  push(state) {
    this.listeners.state({ data: JSON.stringify(state) });
  }
  fail(forGood = false) {
    if (forGood) this.readyState = 2;
    this.listeners.error({});
  }
}

let calls;      // the requests received by the fake fetch: { url, options }
let respond;    // what the fake fetch returns: a function (url, options) → response, which may throw

const response = (body, status = 200) => ({ ok: status < 300, status, json: async () => body });
const TIME = "2026-10-07T07:00:00+02:00";
const state = (more = {}) => ({
  generated: TIME, example: false, error: null, agents: [], events: [], extensions: [], snapshot: null, ...more,
});
const event = (n) => ({ n, t: TIME, kind: "blocked", agent: "w1:p1", text: `trial ${n}` });
const cut = () => {
  throw new TypeError("fetch failed");
};
// Lets the promises in progress finish (setImmediate is not a mocked timer).
const breathe = () => new Promise((done) => setImmediate(done));

function load() {
  delete require.cache[PATH];
  return require(PATH);
}

beforeEach(() => {
  FakeStream.opened = [];
  calls = [];
  respond = () => response(state());
  globalThis.EventSource = FakeStream;
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return respond(url, options);
  };
});

test("the file sets the global Something and its five tools", () => {
  const Something = load();
  assert.equal(globalThis.Something, Something);
  assert.deepEqual(Object.keys(Something).sort(), ["conversation", "onEvent", "send", "state", "watch"]);
});

test("state: returns the state, or fails with a sentence", async () => {
  const Something = load();
  respond = () => response(state({ error: "Herdr does not answer: trial" }));
  assert.equal((await Something.state()).error, "Herdr does not answer: trial");   // an error of Herdr is still a state
  assert.equal(calls[0].url, "/api/state");

  respond = () => response({ error: "host refused" }, 403);
  await assert.rejects(Something.state(), { message: "host refused" });

  respond = cut;
  await assert.rejects(Something.state(), { message: "something does not answer" });

  respond = () => ({ ok: true, status: 200, json: async () => JSON.parse("<html>") });
  await assert.rejects(Something.state(), /200/);   // an unreadable response is never returned as a state
});

test("every request has a timeout of 8 s, after which something does not answer", async (t) => {
  const Something = load();
  const timeouts = [];
  const breaker = new AbortController();
  t.mock.method(AbortSignal, "timeout", (ms) => (timeouts.push(ms), breaker.signal));
  // A silent server: the request only ends if its signal cuts it.
  respond = (url, options) =>
    new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason)));

  const requests = [Something.state(), Something.conversation("w1:p1"), Something.send("w1:p1", "hello")];
  await breathe();
  assert.deepEqual(timeouts, [8000, 8000, 8000]);
  assert.equal(calls[2].options.method, "POST");   // the timeout is added to the options, it does not replace them
  breaker.abort();
  for (const request of requests) await assert.rejects(request, { message: "something does not answer" });
});

test("without AbortSignal.timeout, the request still goes, without a timeout", async (t) => {
  const Something = load();
  const kept = AbortSignal.timeout;
  t.after(() => (AbortSignal.timeout = kept));
  AbortSignal.timeout = undefined;
  assert.equal((await Something.state()).error, null);
  assert.equal(calls[0].options.signal, undefined);
});

test("watch: each state of the stream reaches fn", () => {
  const Something = load();
  const received = [];
  Something.watch((s) => received.push(s));
  assert.equal(FakeStream.opened.length, 1);
  assert.equal(FakeStream.opened[0].url, "/api/stream");
  assert.equal(received.length, 0);   // nothing is made up before the first state

  FakeStream.opened[0].push(state({ agents: [{ id: "w1:p1" }] }));
  FakeStream.opened[0].push(state({ agents: [] }));
  assert.deepEqual(received.map((s) => s.agents.length), [1, 0]);
  assert.equal(calls.length, 0);   // as long as the stream works, no polling
});

test("watch: fallback to polling after three stream failures", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  const Something = load();
  const received = [];
  const stop = Something.watch((s) => received.push(s));
  const stream = FakeStream.opened[0];

  stream.fail();
  stream.fail();
  assert.equal(stream.readyState, 0);   // two failures: the browser reopens the stream by itself
  assert.equal(calls.length, 0);
  stream.fail();
  assert.equal(stream.readyState, 2);   // three: the stream is closed, polling takes over
  await breathe();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/api/state");
  assert.equal(received.length, 1);

  // A state that only changed its time is not given again; a state that changed is.
  respond = () => response(state({ generated: "2026-10-07T07:00:02+02:00" }));
  t.mock.timers.tick(2000);
  await breathe();
  assert.equal(calls.length, 2);
  assert.equal(received.length, 1);
  respond = () => response(state({ agents: [{ id: "w1:p1" }] }));
  t.mock.timers.tick(2000);
  await breathe();
  assert.equal(received.length, 2);
  assert.equal(FakeStream.opened.length, 1);   // the stream is not reopened
  stop();
});

test("watch: a stream closed for good, or no EventSource, leads to polling", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  let Something = load();
  let received = [];
  let stop = Something.watch((s) => received.push(s));
  FakeStream.opened[0].fail(true);
  await breathe();
  assert.equal(received.length, 1);
  stop();

  delete globalThis.EventSource;
  Something = load();
  received = [];
  stop = Something.watch((s) => received.push(s));
  await breathe();
  assert.equal(received.length, 1);
  assert.equal(FakeStream.opened.length, 1);   // no new stream
  stop();
});

test("watch: onLost is called once, then fn when it is back (stream)", () => {
  const Something = load();
  const received = [];
  const outages = [];
  Something.watch((s) => received.push(s), (sentence) => outages.push(sentence));
  const stream = FakeStream.opened[0];
  stream.push(state());
  stream.fail();
  stream.fail();
  assert.deepEqual(outages, ["something no longer answers"]);

  stream.push(state());
  assert.equal(received.length, 2);
  stream.fail();   // a new outage is said again, and the count of failures started again from zero
  stream.fail();
  assert.equal(outages.length, 2);
  assert.equal(stream.readyState, 0);
});

test("watch: onLost is called once, then fn when it is back (polling)", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  delete globalThis.EventSource;
  const Something = load();
  const received = [];
  const outages = [];
  const stop = Something.watch((s) => received.push(s), (sentence) => outages.push(sentence));
  await breathe();
  assert.equal(received.length, 1);

  respond = cut;
  for (let i = 0; i < 3; i++) {
    t.mock.timers.tick(2000);
    await breathe();
  }
  assert.deepEqual(outages, ["something no longer answers"]);
  assert.equal(received.length, 1);

  respond = () => response(state());   // the same state as before the outage: fn is called again all the same
  t.mock.timers.tick(2000);
  await breathe();
  assert.equal(received.length, 2);
  stop();
});

test("watch: the returned function stops the watch", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval"] });
  let Something = load();
  let received = [];
  let stop = Something.watch((s) => received.push(s));
  const stream = FakeStream.opened[0];
  stream.push(state());
  stop();
  stop();   // stopping twice breaks nothing
  assert.equal(stream.readyState, 2);

  // A new watch reopens a connection and receives nothing from the old one.
  Something.watch((s) => received.push(s));
  await breathe();
  assert.equal(FakeStream.opened.length, 2);
  assert.equal(received.length, 1);

  // When polling: no more request after the stop, and a late response is not given.
  delete globalThis.EventSource;
  Something = load();
  received = [];
  calls = [];
  stop = Something.watch((s) => received.push(s));
  stop();
  await breathe();
  t.mock.timers.tick(10000);
  await breathe();
  assert.equal(calls.length, 1);
  assert.equal(received.length, 0);
});

test("watch: several watches share a single connection", async (t) => {
  const logged = t.mock.method(console, "error", () => {});
  const Something = load();
  const a = [];
  const b = [];
  const outages = [];
  const stopA = Something.watch((s) => a.push(s));
  const stream = FakeStream.opened[0];
  stream.push(state({ agents: [{ id: "w1:p1" }] }));

  const stopB = Something.watch((s) => b.push(s), (sentence) => outages.push(sentence));
  Something.watch(() => {
    throw new Error("a page that throws");   // does not deprive the others of the state
  });
  await breathe();
  assert.equal(FakeStream.opened.length, 1);
  assert.equal(b.length, 1);   // the newcomer receives the last state right away
  assert.equal(b[0].agents[0].id, "w1:p1");

  stream.push(state());
  assert.equal(a.length, 2);
  assert.equal(b.length, 2);
  assert.equal(logged.mock.callCount(), 2);   // the page's error shows in the console, thrown twice

  stopA();
  assert.equal(stream.readyState, 0);   // watches remain: the connection stays open
  stream.push(state());
  assert.equal(a.length, 2);
  assert.equal(b.length, 3);
  stream.fail();
  assert.equal(outages.length, 1);
  stopB();
  assert.equal(stream.readyState, 0);   // the third watch still holds the connection
});

test("onEvent: nothing replayed at the first state, then only the new ones", () => {
  const Something = load();
  const received = [];
  const stop = Something.onEvent((e) => received.push(e.n));
  Something.watch(() => {});
  const stream = FakeStream.opened[0];
  assert.equal(FakeStream.opened.length, 1);   // the same stream as watch

  stream.push(state({ events: [event(11), event(12)] }));
  assert.deepEqual(received, []);
  stream.push(state({ events: [event(11), event(12)] }));
  assert.deepEqual(received, []);
  stream.push(state({ events: [event(11), event(12), event(13), event(14)] }));
  assert.deepEqual(received, [13, 14]);
  stream.push(state({ events: [event(13), event(14), event(15)] }));
  assert.deepEqual(received, [13, 14, 15]);

  // something restarted: its counter starts again, and its new events arrive all the same.
  stream.push(state({ events: [] }));
  stream.push(state({ events: [event(1)] }));
  assert.deepEqual(received, [13, 14, 15, 1]);

  stop();
  stream.push(state({ events: [event(1), event(2)] }));
  assert.equal(received.length, 4);
});

test("onEvent: a first state without an event does not hide the first event", () => {
  const Something = load();
  const received = [];
  Something.onEvent((e) => received.push(e.n));
  FakeStream.opened[0].push(state());
  FakeStream.opened[0].push(state({ events: [event(1)] }));
  assert.deepEqual(received, [1]);
});

test("onEvent: an fn that throws does not lose the next events and does not see the same one again", (t) => {
  const logged = t.mock.method(console, "error", () => {});
  const Something = load();
  const received = [];
  Something.onEvent((e) => {
    received.push(e.n);
    if (e.n === 2) throw new Error("a page that throws");
  });
  const stream = FakeStream.opened[0];
  stream.push(state({ events: [event(1)] }));
  stream.push(state({ events: [event(1), event(2), event(3)] }));
  assert.deepEqual(received, [2, 3]);
  assert.equal(logged.mock.callCount(), 1);   // the page's error shows in the console
  stream.push(state({ events: [event(1), event(2), event(3), event(4)] }));
  assert.deepEqual(received, [2, 3, 4]);
});

test("send: X-Something header, success, refusal with the server's sentence, network cut", async () => {
  const Something = load();
  respond = () => response({ ok: true });
  assert.deepEqual(await Something.send("w1:p1", "hello"), { ok: true });
  const { url, options } = calls[0];
  assert.equal(url, "/api/message");
  assert.equal(options.method, "POST");
  assert.equal(options.headers["X-Something"], "1");
  assert.deepEqual(JSON.parse(options.body), { agent: "w1:p1", text: "hello" });

  const refusal = "this agent is waiting for an answer in its pane: something does not write over a question";
  respond = () => response({ error: refusal }, 409);
  await assert.rejects(Something.send("w1:p1", "hello"), { name: "Error", message: refusal });

  respond = cut;
  await assert.rejects(Something.send("w1:p1", "hello"), { message: "something does not answer" });
});

test("conversation: the parameters go into the request", async () => {
  const Something = load();
  const page = { agent: "w1:p1", turns: [], older: false, before: null };
  respond = () => response(page);

  assert.deepEqual(await Something.conversation("w1:p1"), page);
  let request = new URL(calls[0].url, "http://127.0.0.1");
  assert.equal(request.pathname, "/api/conversation");
  assert.deepEqual([...request.searchParams], [["agent", "w1:p1"]]);

  await Something.conversation("w1:p1", { turns: 5, before: "turn 7&x" });
  request = new URL(calls[1].url, "http://127.0.0.1");
  assert.deepEqual(Object.fromEntries(request.searchParams), { agent: "w1:p1", turns: "5", before: "turn 7&x" });

  respond = () => response({ error: "unknown agent" }, 404);
  await assert.rejects(Something.conversation("w9:p9"), { message: "unknown agent" });
});

// ——— The blank page: the script of page/index.html, on a fake document and a fake Something ———

// A fake element: just what the page uses. textContent returns the text of everything it contains.
class FakeElement {
  constructor(tag) {
    Object.assign(this, { tag, children: [], text: "", value: "", listeners: {} });
    this.classList = { add() {}, remove() {} };
  }
  get textContent() {
    return this.text + this.children.map((e) => e.textContent).join("");
  }
  set textContent(text) {
    this.children = [];
    this.text = String(text);
  }
  append(...elements) {
    this.children.push(...elements);
  }
  prepend(...elements) {
    this.children.unshift(...elements);
  }
  replaceChildren(...elements) {
    this.text = "";
    this.children = elements;
  }
  addEventListener(kind, fn) {
    this.listeners[kind] = fn;
  }
  scrollIntoView() {}
  // All the elements of this tag, at any depth.
  all(tag) {
    return this.children.flatMap((e) => [...(e.tag === tag ? [e] : []), ...e.all(tag)]);
  }
}

const SCRIPT = readFileSync(new URL("../page/index.html", import.meta.url), "utf8")
  .match(/<script>([\s\S]*?)<\/script>/)[1];
const agent = (id, more = {}) => ({
  id, name: null, harness: "claude", state: "idle", session: { id: "s1", path: "~/s1.jsonl" }, read_error: null,
  context: null, tool: null, request: null, todos: [], goal: null, subagents: [], activity: TIME, ...more,
});

// Opens the page on these agents; `more`: other keys of the state. Returns $ (an element by its id), `open` (an
// agent's button), `fields` (an agent's card, name → text) and `sends`: the messages sent, which the test
// makes succeed or fail.
function page(agents, turns = [], more = {}) {
  const byId = new Map();
  const $ = (id) => byId.get(id) ?? byId.set(id, new FakeElement("div")).get(id);
  const sends = [];
  let give;
  const Something = {
    watch: (fn) => (give = fn),
    onEvent() {},
    conversation: async () => ({ turns, older: false, before: null }),
    send: (id, text) => new Promise((ok, refuse) => sends.push({ id, text, ok, refuse })),
  };
  const document = { getElementById: $, createElement: (tag) => new FakeElement(tag) };
  new Function("document", "Something", "Node", SCRIPT)(document, Something, FakeElement);
  give(state({ herdr: { connected: true, version: "0.9.3", protocol: 22 }, agents, ...more }));
  const cards = $("agents").children;
  const open = (id) => cards[agents.findIndex((a) => a.id === id)].all("button")[0].onclick();
  const fields = (id) => {
    const [dl] = cards[agents.findIndex((a) => a.id === id)].all("dl");
    return Object.fromEntries(dl.all("dt").map((dt, i) => [dt.textContent, dl.all("dd")[i].textContent]));
  };
  const submit = () => $("write").listeners.submit({ preventDefault() {} });
  return { $, open, fields, sends, submit };
}

test('page: tool, request and goal at null say "none" if the log is read, "unknown" otherwise', () => {
  // The goal says "none found": for a harness whose goal is not read, null does not mean that there is none.
  const { fields } = page([
    agent("read"),
    agent("blocked", { state: "blocked" }),
    agent("state-unknown", { state: "unknown" }),
    agent("asked", { state: "blocked", request: { kind: "question", questions: [] } }),
    agent("no-session", { session: null }),
    agent("unreadable", { read_error: "OSError: log gone" }),
    agent("full", {
      tool: { name: "Bash", since: TIME },
      request: { kind: "permission", tool: "Bash" },
      goal: { objective: "finish", status: "active", tokens: null, seconds: null },
    }),
  ]);
  const three = (id) => ["tool", "request", "goal"].map((name) => fields(id)[name]);
  assert.deepEqual(three("read"), ["none", "none", "none found"]);
  assert.deepEqual(three("blocked"), ["none", "unknown", "none found"]);   // it waits: the log does not say for what
  assert.deepEqual(three("state-unknown"), ["none", "unknown", "none found"]);
  assert.equal(fields("asked").request, "question · unknown");        // a question was asked, and could not be read
  assert.deepEqual(three("no-session"), ["unknown", "unknown", "unknown"]);
  assert.deepEqual(three("unreadable"), ["unknown", "unknown", "unknown"]);
  assert.match(fields("full").tool, /^Bash · since/);
  assert.equal(fields("full").request, "permission · tool: Bash");
  assert.match(fields("full").goal, /^finish · active/);
  assert.equal(fields("read").context, "unknown");   // any other value at null stays unknown
});

test("page: a question without options is still written, and does not freeze the page", () => {
  const questions = [{ question: "Which one?", multi: false },
                     { question: "Which ones?", options: ["a", "b"], multi: true }];
  const { $, fields } = page([agent("w1:p1", { request: { kind: "question", questions } }), agent("w1:p2")]);
  assert.match(fields("w1:p1").request, /^Which one\?.*Which ones\? — a \/ b \(several choices\)$/);
  assert.equal($("agents").children.length, 2);   // the next agent is shown too
});

test("page: opening another agent empties the field, reopening the same one keeps it", async () => {
  const { $, open } = page([agent("w1:p1"), agent("w1:p2")]);
  open("w1:p1");
  $("text").value = "for the first";
  open("w1:p1");
  assert.equal($("text").value, "for the first");
  open("w1:p2");
  assert.equal($("text").value, "");
  await breathe();
});

test("page: the answer to a send is said even if another agent was opened, whose field is left alone", async () => {
  const said = { ok: "Message sent to w1:p1.", refuse: "Message to w1:p1: unknown agent" };
  for (const outcome of ["ok", "refuse"]) {
    const { $, open, sends, submit } = page([agent("w1:p1"), agent("w1:p2")]);
    open("w1:p1");
    $("text").value = "for the first";
    const done = submit();
    assert.deepEqual([sends[0].id, sends[0].text], ["w1:p1", "for the first"]);
    open("w1:p2");
    $("text").value = "for the second";
    sends[0][outcome](outcome === "ok" ? { ok: true } : new Error("unknown agent"));
    await done;
    assert.equal($("text").value, "for the second");
    assert.equal($("feedback").textContent, said[outcome]);   // a failure nobody sees would pass for a message sent
    assert.equal($("send").disabled, false);
  }
});

test("page: the answer to a send applies to the agent that stayed open", async () => {
  const { $, open, sends, submit } = page([agent("w1:p1")]);
  open("w1:p1");
  $("text").value = "hello";
  let done = submit();
  sends[0].ok({ ok: true });
  await done;
  assert.equal($("text").value, "");
  assert.equal($("feedback").textContent, "Message sent to w1:p1.");

  $("text").value = "again";
  done = submit();
  sends[1].refuse(new Error("unknown agent"));
  await done;
  assert.equal($("text").value, "again");   // a refused message stays in the field
  assert.equal($("feedback").textContent, "unknown agent");

  // Without an answer the message may have left; a failure before anything was written to Herdr leaves no doubt.
  const doubt = ". The message may have left all the same: look at the pane before sending it again.";
  // The two sentences something.js writes itself are taken from it: a connection cut, an answer that is not JSON.
  const own = [];
  for (respond of [cut, () => ({ ok: true, status: 200, json: async () => { throw new SyntaxError("not JSON"); } })]) {
    own.push(await load().send("w1:p1", "hello").then(() => assert.fail("sent"), (error) => error.message));
  }
  assert.deepEqual(own, ["something does not answer", "something answered badly (200)"]);
  // The others come from the core, where the blank page reads these very words: change them in both places.
  const core = ["herdr.py", "server.py"].map((file) => readFileSync(require.resolve(`../something/${file}`), "utf8"));
  for (const words of ['"socket missing"', '"connection refused"', "Herdr does not answer: "]) {
    assert.ok(core.join("\n").includes(words), `${words} is no longer written by the core`);
  }
  for (const [sentence, said] of [
    ["Herdr does not answer: timed out (~/herdr.sock)", doubt],
    ["Herdr does not answer: connection closed without a response", doubt],
    ["Herdr does not answer: unreadable response", doubt],
    [own[0], doubt],
    [own[1], doubt],
    ["Herdr does not answer: socket missing (~/herdr.sock)", ""],
    ["Herdr does not answer: connection refused (~/herdr.sock)", ""],
    ["Herdr refuses the message: the pane does not answer", ""],
  ]) {
    done = submit();
    sends.at(-1).refuse(new Error(sentence));
    await done;
    assert.equal($("feedback").textContent, sentence + said);
    assert.equal($("text").value, "again");
  }
});

test("page: a tool without a target is written by its name alone", async () => {
  const tools = [{ name: "Read", target: "~/something/README.md" }, { name: "TodoWrite", target: null }];
  const { $, open } = page([agent("w1:p1")], [{ id: "t1", t: TIME, from: "user", text: "hello",
                                                replies: [], tools, end: null }]);
  open("w1:p1");
  await breathe();
  assert.deepEqual($("turns").all("li").slice(1).map((li) => li.textContent),
    ["Read ~/something/README.md", "TodoWrite"]);
});

// The lines of a list of the page, at any depth: the <li> that contain no other.
const lines = (element) => element.all("li").filter((li) => !li.all("li").length).map((li) => li.textContent);

test("page: the agents are counted by state, and the one that waits for you is said so", () => {
  const agents = [agent("w1:p1"), agent("w1:p2", { state: "blocked" }), agent("w1:p3", { state: "working" }),
                  agent("w1:p4", { state: "working" }), agent("w1:p5", { state: "never heard of" })];
  const { $ } = page(agents);
  assert.equal($("count").textContent, "1 blocked · 2 working · 1 idle");   // a state it does not know: not counted
  assert.equal($("count").hidden, false);
  const headings = $("agents").all("h3");
  assert.deepEqual(headings.map((h) => h.textContent).slice(0, 2),
    ["w1:p1 · claude · idle", "w1:p2 · claude · blocked: it waits for you"]);
  assert.deepEqual(headings.map((h) => h.className).slice(0, 2), [undefined, "waiting"]);
  assert.equal(page([]).$("count").hidden, true);
  assert.equal(page([]).$("agents").textContent, "No agent in Herdr: start one in a pane, it shows up here.");
});

test("page: a number keeps four decimals, and what is not known steps back", () => {
  const context = { tokens: 182000, window: null, percent: null };
  // A title that reads like a missing value is a title all the same.
  const { $, fields } = page([agent("w1:p1", { cost: 0.0004, context, title: "none", todos: null })]);
  assert.equal(fields("w1:p1").cost, "$0.0004");    // never "$0" for a small cost
  assert.equal(fields("w1:p1").context, "182,000 tokens · window: unknown · percent: unknown");
  const [dl] = $("agents").all("dl");
  const muted = Object.fromEntries(dl.all("dt").map((dt, i) =>
    [dt.textContent, dl.all("dd")[i].all("span").map((span) => span.className).join()]));
  assert.deepEqual([muted.name, muted.tool, muted.goal, muted.todos, muted.subagents],
    ["absent", "absent", "absent", "absent", "absent"]);
  assert.deepEqual([muted.title, muted.cost, muted.id, muted.harness], ["", "", "", ""]);
  assert.deepEqual([fields("w1:p1").title, fields("w1:p1").todos, fields("w1:p1").goal],
    ["none", "unknown", "none found"]);
});

// What the tests above cannot see: they run the script on a fake document that makes up any element asked for.
test("page: each element the script asks for is in the HTML, and the page asks the server for no icon", () => {
  const html = readFileSync(new URL("../page/index.html", import.meta.url), "utf8");
  const declared = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
  const asked = new Set([...SCRIPT.matchAll(/\$\("([^"]+)"\)/g)].map((match) => match[1]));
  assert.equal(new Set(declared).size, declared.length, "an id is declared once");
  assert.deepEqual([...asked].filter((id) => !declared.includes(id)), []);
  assert.ok(asked.size > 10);
  assert.match(html, /<link rel="icon" href="data:,">/);    // without it, a browser asks for /favicon.ico: a 404
});

test("page: an outage of Herdr says what to look at, another failure is said as is", () => {
  const down = { herdr: { connected: false, version: null, protocol: null } };
  const missing = "Herdr does not answer: socket missing (~/.config/herdr/herdr.sock)";
  let { $ } = page([], [], { ...down, error: missing });
  assert.equal($("outage").textContent,
    `${missing}. Is a Herdr session running? something keeps asking, and comes back by itself.`);
  assert.equal($("outage").hidden, false);
  assert.equal($("agents").textContent, "Unknown: Herdr is not connected.");
  ({ $ } = page([], [], { ...down, error: "no poll for more than 20 s: something's loop is blocked or stopped" }));
  assert.equal($("outage").textContent, "no poll for more than 20 s: something's loop is blocked or stopped");
  ({ $ } = page([agent("w1:p1")]));
  assert.deepEqual([$("outage").textContent, $("outage").hidden], ["", true]);
  assert.match($("herdr").textContent,
    /^Herdr connected · version: 0\.9\.3 · protocol: 22 · last state received: poll of /);
});

test("page: example data is said to be so, and only it", () => {
  assert.equal(page([agent("w1:p1")]).$("example").hidden, true);
  assert.equal(page([agent("w1:p1")], [], { example: true }).$("example").hidden, false);
});

test("page: each extension, with its harness or the reason it was rejected", () => {
  const extensions = [
    { name: "claude", harness: "claude", error: null },
    { name: "draft", harness: null, error: "HARNESS is missing" },
  ];
  assert.deepEqual(lines(page([], [], { extensions }).$("extensions")),
    ["claude · harness: claude", "draft · harness: unknown · not loaded: HARNESS is missing"]);
  assert.equal(page([]).$("extensions").textContent, "none");
});

test("page: Herdr's tree, where a pane without an agent is a terminal", () => {
  const snapshot = {
    workspaces: [{ workspace_id: "w1", label: "trial" }, { workspace_id: "w2", label: "empty" }],
    tabs: [
      { tab_id: "w1:t1", workspace_id: "w1", label: "one" },
      { tab_id: "w1:t2", workspace_id: "w1", label: "two" },
    ],
    panes: [
      { pane_id: "w1:p1", tab_id: "w1:t1", agent: "claude" },
      { pane_id: "w1:p2", tab_id: "w1:t1" },
      { pane_id: "w1:p3", tab_id: "w1:t2", agent: null },
    ],
  };
  const tree = page([agent("w1:p1")], [], { snapshot }).$("tree");
  assert.deepEqual(lines(tree), ["w1:p1 · claude", "w1:p2 · terminal", "w1:p3 · terminal", "empty"]);
  assert.match(tree.textContent, /^trialtab one.*tab two/);
  assert.equal(page([]).$("tree").textContent, "unknown");   // without a snapshot, Herdr is not connected
});

const EXAMPLE = JSON.parse(readFileSync(new URL("../page/example.json", import.meta.url), "utf8")).state;

test("page: the repo's example state is shown in full", () => {
  const { $, fields } = page(EXAMPLE.agents, [], EXAMPLE);
  assert.equal($("example").hidden, false);
  assert.equal($("agents").children.length, 6);
  assert.equal(fields("w2R:p1").tool, "none");       // a log that was read, with no tool in progress
  assert.equal(fields("w1K:p4").request, "unknown"); // it waits for you, and its log does not say for what
  assert.equal($("count").textContent, "2 blocked · 1 working · 1 done · 1 idle · 1 unknown");
  assert.equal(fields("w2R:p2").tool, "unknown");    // a harness without an extension
  assert.equal(fields("w2R:p3")["log not read"], "the pane does not safely link to any session");
  assert.ok(lines($("tree")).includes("w1K:p3 · terminal"));
  assert.equal(lines($("extensions")).length, EXAMPLE.extensions.length);
});

// What each reader expects from Herdr to link a pane: the kind of its `agent_session`. Claude Code does without,
// and it is the only one whose subagents never have a parent other than the pane.
const LINKS = { omp: "path", pi: "path", codex: "id", opencode: "id" };

test("example: a session has the link its reader asks for, a subagent a parent it can return", () => {
  const { agents, snapshot } = EXAMPLE;
  for (const a of agents) {
    const kind = LINKS[a.harness];
    for (const raw of [...snapshot.agents, ...snapshot.panes].filter((r) => kind && r.pane_id === a.id)) {
      const ref = raw.agent_session;
      assert.equal(Boolean(ref), Boolean(a.session), `${a.id}: linked if Herdr names its session, and only then`);
      if (!ref) continue;
      assert.deepEqual([ref.agent, ref.kind], [a.harness, kind], a.id);
      assert.equal(ref.value, kind === "id" ? a.session.id : a.session.path.replace("~", "/Users/example"), a.id);
    }
    const siblings = (a.subagents ?? []).map((s) => s.id);
    for (const s of a.subagents ?? []) {
      assert.ok(s.parent === a.id || (a.harness !== "claude" && siblings.includes(s.parent)), `${a.id}: ${s.id}`);
    }
  }
});
