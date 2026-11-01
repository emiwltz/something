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
    case "send": return something.send(p.agent, p.text, "when" in p || "command" in p ? pick(["when", "command"]) : undefined);
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
  assert.deepEqual(copy(Object.keys(something.granted).sort()), ["agents", "folder", "limits", "listed", "refused", "rights", "unavailable"]);
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

test("where the page has reportError, a listener's error reaches it with its own file and line", () => {
  const reported = [];
  const window = { webkit: { messageHandlers: { something: { postMessage: () => Promise.resolve({}) } } } };
  vm.runInNewContext(source, { window, setTimeout: () => assert.fail("no timer"), reportError: (error) => reported.push(error.message) });
  window.something.on("change", () => { throw new Error("Invented failure."); });
  window.something._push({});
  assert.deepEqual(reported, ["Invented failure."]);
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

test("a post that throws (a value WebKit cannot copy) rejects with BAD_PARAMS instead of throwing", async () => {
  const window = { webkit: { messageHandlers: { something: { postMessage: () => { throw new Error("DataCloneError"); } } } } };
  vm.runInNewContext(source, { window, setTimeout });
  let promise;
  assert.doesNotThrow(() => { promise = window.something.store.set("x", () => {}); });
  await assert.rejects(promise, (error) => error.code === "BAD_PARAMS" && error.message.endsWith("."));
});

test("a transport rejection that carries a code keeps it", async () => {
  const coded = Object.assign(new Error("Invented."), { code: "BUSY" });
  const window = { webkit: { messageHandlers: { something: { postMessage: () => Promise.reject(coded) } } } };
  vm.runInNewContext(source, { window, setTimeout });
  await assert.rejects(window.something.open("https://example.com"), (error) => error.code === "BUSY");
});

// The one HTML file, in a page made by hand: the block's scripts run in order, as a browser runs them, over a fake DOM
// that has only what offline.js touches. There is no browser here: what only a real one can show (the parser's order,
// CSP, blob: and localStorage on file://) is in Tests/somethingTests/ExportFileTests.swift for WebKit.
const offline = readFileSync(new URL("offline.js", share), "utf8");

function fixture(name) {
  const html = readFileSync(new URL(`contract/exports/${name}.html`, share), "utf8");
  const [, before, block, after] = html.match(/^([^]*?)<!-- something export -->\n([^]*?)<!-- \/something export -->\n([^]*)$/);
  return { before, after, block, data: JSON.parse(block.match(/id="something-export">(.*?)<\/script>/s)[1]) };
}

function opened(exported, { rights = ["store"], webkit, stored = {}, noStorage = false } = {}) {
  const created = [], watchers = [];
  const elements = {
    "something-export": { textContent: JSON.stringify(exported) },
    something: { textContent: JSON.stringify({ contract: 1, rights }) },
  };
  const localStorage = noStorage ? undefined : { getItem: (key) => stored[key] ?? null, setItem: (key, value) => { stored[key] = value; } };
  const context = {
    localStorage, URL: Object.assign(function (...args) { return new URL(...args); }, { createObjectURL: (blob) => { created.push(blob); return `blob:null/${created.length}`; } }),
    Blob, Response, atob, Uint8Array, JSON, Object, Array, Promise, decodeURIComponent, setTimeout,
    document: { getElementById: (id) => elements[id] ?? null, baseURI: "file:///Users/example/Downloads/board.html" },
    MutationObserver: class { constructor(fn) { this.fn = fn; watchers.push(this); } observe(target, options) { this.options = options; } },
  };
  const window = { fetch: async (input) => `the network: ${input}`, webkit };
  context.window = window;
  vm.runInNewContext(source, context);
  vm.runInNewContext(offline, context);
  // An element the parser adds: the records a browser would hand the observer.
  const add = (name, value) => {
    const attributes = { [name]: value };
    const element = { nodeType: 1, hasAttribute: (key) => key in attributes, getAttribute: (key) => attributes[key],
      setAttribute: (key, next) => { attributes[key] = next; }, querySelectorAll: () => [], attributes };
    watchers[0].fn([{ type: "childList", addedNodes: [element] }]);
    return attributes[name];
  };
  return { something: window.something, window, add, created, watchers, stored };
}

test("each one-file fixture holds the block in order, with the scripts as they stand when it was written", () => {
  for (const name of ["file", "folder"]) {
    const { before, block, after } = fixture(name);
    assert.equal(before, "<!doctype html>");
    assert.ok(after.startsWith("\n<title>"));
    assert.ok(block.indexOf('<meta charset="utf-8">') === 0, "charset first: browsers look only in the first 1,024 bytes");
    const order = ["Content-Security-Policy", 'id="something-export"', "if (!window.something)", "exported.name"].map((word) => block.indexOf(word));
    assert.deepEqual(order, order.slice().sort((a, b) => a - b));
    assert.ok(!/default-src[^"]*(http|\*|self)/.test(block), "no network, no origin of its own");
  }
});

test("a browser: every agent call rejects NO_HOST with its sentence, and no agent is granted", async () => {
  const { something } = opened(fixture("file").data);
  for (const call of [something.state(), something.send("a", "hi"), something.interrupt("a"), something.set("a", {}), something.launch("claude"), something.resume("claude", "t"), something.open("https://example.com")]) {
    await assert.rejects(call, (error) => error.code === "NO_HOST" && /open the space in something/.test(error.message));
  }
  assert.deepEqual(JSON.parse(JSON.stringify(something.granted)), { rights: ["store"], refused: [], unavailable: [], limits: {}, agents: { folders: [] }, folder: null });
  assert.equal(something.contract, 1);
  assert.equal(typeof something.on("change", () => {}), "function", "a page that listens at load does not throw");
});

test("the fixture's own scripts run the same way", async () => {
  const { block, data } = fixture("folder");
  const scripts = [...block.matchAll(/<script>([^]*?)<\/script>/g)].map((match) => match[1]);
  const window = {}, context = { window, document: { getElementById: (id) => (id === "something-export" ? { textContent: JSON.stringify(data) } : null), baseURI: "file:///x/" },
    MutationObserver: class { observe() {} }, URL, Blob, Response, atob, Uint8Array, JSON, Object, Promise, localStorage: undefined };
  scripts.forEach((script) => vm.runInNewContext(script, context));
  await assert.rejects(window.something.state(), (error) => error.code === "NO_HOST");
});

test("store works over the memory the file carries, as the engine's does", async () => {
  const { something, stored } = opened(fixture("folder").data);
  assert.deepEqual(JSON.parse(JSON.stringify(await something.store.get(""))), { seen: ["a1"], theme: "dark" });
  assert.equal(await something.store.get("theme"), "dark");
  assert.equal(await something.store.get("seen/0"), null, "a list has no keys");
  assert.equal(await something.store.get("nothing/here"), null);
  await something.store.set("plans/saturday", "Market at nine.");
  assert.equal(await something.store.get("plans/saturday"), "Market at nine.");
  await something.store.set("theme", null);
  assert.equal(await something.store.get("theme"), null);
  await something.store.set("gone/deep", null);
  assert.equal(await something.store.get("gone"), null, "removing makes no objects on the way");
  await assert.rejects(something.store.get("a//b"), (error) => error.code === "BAD_PARAMS");
  await assert.rejects(something.store.set("seen/x", 1), (error) => error.code === "BAD_PARAMS");
  await assert.rejects(something.store.set("", 3), (error) => error.code === "BAD_PARAMS");
  await assert.rejects(something.store.set("big", "x".repeat(5000001)), (error) => error.code === "STORE_FULL");
  assert.equal(await something.store.get("big"), null);
  // Kept in the browser: the next opening finds it; another export of the space starts from its own memory.
  const again = opened(fixture("folder").data, { stored });
  assert.equal(await again.something.store.get("plans/saturday"), "Market at nine.");
  const later = opened({ ...fixture("folder").data, exported: "2027-01-01T00:00:00Z" }, { stored });
  assert.equal(await later.something.store.get("plans/saturday"), null);
});

test("a file with no memory starts empty; a browser that keeps nothing still works", async () => {
  const { something } = opened(fixture("file").data, { noStorage: true });
  assert.deepEqual(JSON.parse(JSON.stringify(await something.store.get(""))), {});
  await something.store.set("note", "tea");
  assert.equal(await something.store.get("note"), "tea");
});

test("a page that does not declare store has no store, as in something", async () => {
  const { something } = opened(fixture("folder").data, { rights: [] });
  assert.deepEqual([...something.granted.rights], []);
  await assert.rejects(something.store.get("theme"), (error) => error.code === "NO_HOST");
});

test("inside something it does nothing: the real bridge stays", () => {
  const webkit = { messageHandlers: { something: { postMessage: () => Promise.resolve({ result: null }) } } };
  const { something, watchers } = opened(fixture("folder").data, { webkit });
  assert.equal(watchers.length, 0);
  assert.ok(Object.prototype.hasOwnProperty.call(something, "_push"), "the same object something.js made");
});

test("a folder's files: src and href become blob URLs, fetch answers, anything else is left alone", async () => {
  const { add, window, created, watchers } = opened(fixture("folder").data);
  assert.deepEqual(JSON.parse(JSON.stringify(watchers[0].options.attributeFilter)), ["src", "href"]);
  assert.equal(add("src", "img/logo.svg"), "blob:null/1");
  assert.equal(add("src", "./img/logo.svg?v=1"), "blob:null/2");
  assert.equal(add("href", "/img/logo.svg"), "blob:null/3");
  assert.equal(created[0].type, "image/svg+xml");
  assert.match(await created[0].text(), /<svg/);
  for (const address of ["https://example.com/img/logo.svg", "#top", "index.html", "other.png", "mailto:a@example.com"]) {
    assert.equal(add("href", address), address);
  }
  assert.equal(created.length, 3);
  const answer = await window.fetch("img/logo.svg");
  assert.match(await answer.text(), /<svg/);
  assert.equal(answer.headers.get("Content-Type"), "image/svg+xml");
  assert.match(await (await window.fetch("file:///Users/example/Downloads/img/logo.svg")).text(), /<svg/);
  assert.equal(await window.fetch("https://example.com/"), "the network: https://example.com/");
});

test("a file space has no observer to run", () => {
  assert.equal(opened(fixture("file").data).watchers.length, 0);
});
