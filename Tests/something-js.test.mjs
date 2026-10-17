// The tests of share/something.js, on node's own test runner, no dependency: `node --test Tests/something-js.test.mjs`.
// Each case of share/contract/bridge/ is played through a fake host: the page's call must send exactly the
// fixture's request, and the fixture's answer must come back as the result or as an error with its code.
// This checks the JavaScript half of the contract on its own, whatever engine answers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import vm from "node:vm";

const share = new URL("../share/", import.meta.url);
const source = readFileSync(new URL("something.js", share), "utf8");

// Values crossing the transport are copied, as WebKit copies them; the copy is also a plain object of this realm.
const copy = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));

// A fresh page with the bridge loaded. `answer(message)` plays the engine; without it there is no host.
// The page's timers run at once, and what they throw is kept in `uncaught`, as a browser would report it.
function page(answer) {
  const sent = [], uncaught = [];
  const window = {};
  if (answer) {
    window.webkit = { messageHandlers: { something: { postMessage: (m) => { sent.push(copy(m)); return Promise.resolve(copy(answer(m))); } } } };
  }
  const setTimeout = (fn) => { try { fn(); } catch (error) { uncaught.push(error.message); } };
  vm.runInNewContext(source, { window, setTimeout });
  return { something: window.something, sent, uncaught };
}

// The page-side call that sends a request of this method with these params.
function play(something, method, p) {
  const pick = (keys) => Object.fromEntries(keys.filter((k) => k in p).map((k) => [k, p[k]]));
  switch (method) {
    case "state": return something.state();
    case "send": return something.send(p.agent, p.text, "when" in p ? { when: p.when } : undefined);
    case "interrupt": return something.interrupt(p.agent);
    case "set": return something.set(p.agent, pick(["model", "mode", "effort"]));
    case "launch": return something.launch(p.kind, pick(["folder", "model", "mode", "effort"]));
    case "resume": return something.resume(p.kind, p.thread);
    case "store.get": return something.store.get(p.path);
    case "store.set": return something.store.set(p.path, p.value);
    case "open": return something.open(p.url);
    default: return null;
  }
}

const folder = new URL("contract/bridge/", share);
const cases = readdirSync(folder).filter((name) => name.endsWith(".json")).sort();

test("there are bridge cases to play", () => assert.ok(cases.length >= 3));

for (const name of cases) {
  const fixture = JSON.parse(readFileSync(new URL(name, folder), "utf8"));
  test(`bridge case ${name}: ${fixture.about}`, async () => {
    const { something, sent } = page(() => fixture.answer);
    const { method, params } = fixture.request;
    const promise = play(something, method, params);
    if (promise === null) {
      // A function outside contract 1 is not offered at all: the page cannot call it.
      assert.equal(something[method], undefined, `${method} should not exist`);
      return;
    }
    assert.deepEqual(sent, [fixture.request]);
    if (fixture.answer.error) {
      await assert.rejects(promise, (error) => Object.prototype.toString.call(error) === "[object Error]" && error.code === fixture.answer.error.code);
    } else {
      assert.deepEqual(copy(await promise), fixture.answer.result);
    }
  });
}

test("outside something every call rejects with NO_HOST and a sentence", async () => {
  const { something } = page(null);
  for (const promise of [something.state(), something.send("a1", "Hello."), something.store.get(""), something.open("https://example.com")]) {
    await assert.rejects(promise, (error) => error.code === "NO_HOST" && error.message.length > 10);
  }
});

test("contract is 1 and granted has every key before the engine sets it", () => {
  const { something } = page(() => ({}));
  assert.equal(something.contract, 1);
  assert.deepEqual(copy(Object.keys(something.granted).sort()), ["agents", "folder", "limits", "refused", "rights", "unavailable"]);
  assert.equal(something.granted.folder, null);
});

test("on throws UNKNOWN_EVENT at once, and its result unsubscribes", () => {
  const { something } = page(() => ({}));
  assert.throws(() => something.on("changed", () => {}), (error) => error.code === "UNKNOWN_EVENT");
  const seen = [];
  const off = something.on("change", (state) => seen.push(state.at));
  something._push({ at: "2026-10-17T09:00:00Z" });
  off();
  something._push({ at: "2026-10-17T09:00:01Z" });
  assert.deepEqual(seen, ["2026-10-17T09:00:00Z"]);
});

test("_granted replaces granted and tells the granted listeners", () => {
  const { something } = page(() => ({}));
  const told = [];
  something.on("granted", (g) => told.push(g.rights));
  const next = { rights: ["state"], refused: ["store"], unavailable: [], limits: {}, agents: { see: "all" }, folder: null };
  something._granted(next);
  assert.deepEqual(copy(something.granted.rights), ["state"]);
  assert.deepEqual(told, [["state"]]);
});

test("a listener that throws does not stop the next one", () => {
  const { something, uncaught } = page(() => ({}));
  const seen = [];
  something.on("change", () => { throw new Error("Invented failure."); });
  something.on("change", () => seen.push("second"));
  something._push({});
  assert.deepEqual(seen, ["second"]);
  assert.deepEqual(uncaught, ["Invented failure."]);
});

test("send, set and launch leave out what is not given (the engine defaults when to next), store.set sends null for undefined", async () => {
  const { something, sent } = page(() => ({ result: null }));
  await something.send("a1", "Hello.");
  await something.set("a1", { mode: "plan" });
  await something.launch("claude");
  await something.store.set("draft", undefined);
  await something.resume("codex", "019a0000-0000-7000-8000-000000000002");
  assert.deepEqual(sent.map((m) => m.params), [
    { agent: "a1", text: "Hello." },
    { agent: "a1", mode: "plan" },
    { kind: "claude" },
    { path: "draft", value: null },
    { kind: "codex", thread: "019a0000-0000-7000-8000-000000000002" },
  ]);
  assert.deepEqual(sent.map((m) => m.id), [1, 2, 3, 4, 5]);
});

test("every function of frozen-v1.json is there", () => {
  const { something } = page(() => ({}));
  const frozen = JSON.parse(readFileSync(new URL("contract/frozen-v1.json", share), "utf8"));
  for (const name of frozen.functions) {
    const value = name.split(".").reduce((object, key) => object && object[key], something);
    assert.notEqual(value, undefined, `${name} is missing`);
  }
});
