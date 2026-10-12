/* something: the page's tools.

   A page plugs in with <script src="/something.js"></script>, then uses the global `Something` to read the agents'
   state, watch it, read a conversation and send a message to an agent. What the state holds: README, "The state".
   No dependency. Every text returned comes from the agents: set it with textContent, so it never becomes HTML. */
(function () {
  "use strict";

  const POLL = 2000;           // milliseconds between two polls, when the stream does not work
  const FAILURES = 3;          // stream failures, in a row, before falling back to polling
  const TIMEOUT = 8000;        // milliseconds left to the server to answer a request
  const LOST = "something no longer answers";

  const watchers = new Set();  // one { fn, onLost } per watch in progress
  let stream = null;           // the connection to the stream, shared by all watches
  let polling = null;          // the fallback's timer
  let failures = 0;
  let lost = false;
  let last = null;             // the last state received

  // A request to the server. Returns the response's JSON, or fails with the server's sentence. A server silent
  // for eight seconds does not answer; where AbortSignal.timeout does not exist, the request goes without a timeout.
  async function request(path, options) {
    const signal = globalThis.AbortSignal?.timeout?.(TIMEOUT);
    const response = await fetch(path, { ...options, signal }).catch(() => {
      throw new Error("something does not answer");
    });
    const body = await response.json().catch(() => null);
    if (!response.ok || body === null) throw new Error(body?.error ?? `something answered badly (${response.status})`);
    return body;
  }

  // Tells a watcher what is true now: the outage, or the last state.
  function tell(watcher) {
    try {
      if (lost) watcher.onLost?.(LOST);
      else if (last) watcher.fn(last);
    } catch (error) {
      console.error(error);    // a page that throws does not deprive the other watchers
    }
  }

  function receive(state) {
    failures = 0;
    lost = false;
    last = state;
    watchers.forEach(tell);
  }

  function lose() {
    if (lost) return;          // an outage is said once
    lost = true;
    watchers.forEach(tell);
  }

  // Opens the stream. The browser reopens it by itself after a cut; at the third failure in a row, or if the
  // stream is closed for good, we switch to polling and stay there.
  function connect() {
    if (typeof EventSource === "undefined") return poll();
    stream = new EventSource("/api/stream");
    stream.addEventListener("state", (message) => receive(JSON.parse(message.data)));
    stream.addEventListener("error", () => {
      lose();
      if (++failures < FAILURES && stream.readyState !== 2) return;
      stream.close();
      stream = null;
      poll();
    });
  }

  // The fallback: ask for the state every two seconds and, like the stream, only give it if it has changed.
  function poll() {
    let seen = null;           // the last state given, without the time of its poll
    const round = async () => {
      const state = await request("/api/state").catch(() => null);
      if (polling === null) return;   // the watch stopped during the request
      if (state === null) return lose();
      const image = JSON.stringify({ ...state, generated: null });
      if (lost || image !== seen) receive(state);
      seen = image;
    };
    polling = setInterval(round, POLL);
    round();
  }

  function disconnect() {
    stream?.close();
    clearInterval(polling);
    stream = polling = last = null;
    failures = 0;
    lost = false;
  }

  // Calls fn(state) right away, then at each change. If the server no longer answers, calls onLost(sentence)
  // once, resumes by itself, and calls fn again when it is back. Returns the function that stops the watch.
  function watch(fn, onLost) {
    const watcher = { fn, onLost };
    watchers.add(watcher);
    if (watchers.size === 1) connect();
    else queueMicrotask(() => watchers.has(watcher) && tell(watcher));   // what the other watchers already know
    return () => {
      if (watchers.delete(watcher) && !watchers.size) disconnect();
    };
  }

  // Calls fn(event) for each new event. Those the first state already carries are not replayed.
  function onEvent(fn) {
    let seen = null;           // the highest `n` of the last state; null before the first
    return watch((state) => {
      const events = state.events ?? [];
      const fresh = seen === null ? [] : events.filter((e) => e.n > seen);
      seen = Math.max(-1, ...events.map((e) => e.n));   // read again at each state: a restarted server recounts
      for (const event of fresh) {
        try {
          fn(event);
        } catch (error) {
          console.error(error);    // a page that throws does not lose the next ones and does not see this one again
        }
      }
    });
  }

  // Returns { turns, older, before }: an agent's last turns, or those before the cursor `before`.
  function conversation(id, { turns, before } = {}) {
    const query = new URLSearchParams({ agent: id });
    if (turns != null) query.set("turns", turns);
    if (before != null) query.set("before", before);
    return request(`/api/conversation?${query}`);
  }

  // Sends a message to an agent. Fails with the server's sentence if the message was not sent.
  function send(id, text) {
    return request("/api/message", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Something": "1" },
      body: JSON.stringify({ agent: id, text }),
    });
  }

  const Something = { state: () => request("/api/state"), watch, onEvent, conversation, send };
  globalThis.Something = Something;
  if (typeof module !== "undefined") module.exports = Something;   // for the tests, under Node
})();
