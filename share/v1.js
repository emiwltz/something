// V1 tools a page used to talk to something, kept for the template page until the space window (slice 5) moves it
// to something.js, contract 1 bridge. Plain JavaScript, no dependency. Load it from something://app/v1.js.
(function () {
  const subscribers = [];

  function call(method, params) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.something;
    if (!handler) {
      return Promise.reject(new Error("No something host here. Open this page with the `something` command."));
    }
    return handler.postMessage({ method: method, params: params || {} }).then(function (answer) {
      if (answer && "error" in answer) throw new Error(answer.error);
      return answer.result;
    });
  }

  window.something = {
    /** A snapshot of the whole state. What is not known is null. */
    state: function () { return call("state"); },
    /** Calls fn(state) each time the state changes. */
    subscribe: function (fn) { subscribers.push(fn); },
    /** Launches an agent; something asks the person for the folder. Resolves to the agent's id. */
    launch: function (harness) { return call("launch", { harness: harness || "claude" }); },
    /** Sends a message; something asks the person first. Rejects when they refuse. */
    send: function (agent, text) { return call("send", { agent: agent, text: text }); },
    /** The page's own memory, kept between launches: store.get(key), store.set(key, value). null removes. */
    store: {
      get: function (key) { return call("store.get", { key: key }); },
      set: function (key, value) { return call("store.set", { key: key, value: value === undefined ? null : value }); },
    },
    /** Called by the host. Not for pages. */
    _changed: function (state) { subscribers.forEach(function (fn) { fn(state); }); },
  };
})();
