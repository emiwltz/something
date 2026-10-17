// The bridge a space talks to something through: contract 1, section 4. Plain JavaScript, no dependency.
// The engine injects it before the page's scripts, then calls _granted and _push. Any engine that answers the
// transport of contract 4.4 can host it; on the Mac the transport is WebKit's "something" message handler.
(function () {
  "use strict";
  const listeners = { change: [], granted: [] };
  let granted = { rights: [], refused: [], unavailable: [], limits: {}, agents: { folders: [] }, folder: null };
  let next = 1;

  // An Error with a code of contract 4.3, so a page can branch on .code and show .message.
  function failure(code, message) {
    const error = new Error(message);
    error.code = code;
    return error;
  }

  function host() {
    const webkit = window.webkit;
    return webkit && webkit.messageHandlers && webkit.messageHandlers.something;
  }

  function call(method, params) {
    const handler = host();
    if (!handler) {
      return Promise.reject(failure("NO_HOST", "This page is not open in something; open the space in something to reach its agents."));
    }
    const request = { contract: 1, id: next++, method: method, params: params };
    // Inside the promise, so a post that throws (WebKit cannot copy a function, for example) rejects instead.
    return new Promise(function (resolve) { resolve(handler.postMessage(request)); })
      .then(function (answer) {
        if (answer && answer.error) throw failure(answer.error.code, answer.error.message);
        return answer && answer.result !== undefined ? answer.result : null;
      }, function (error) {
        if (error && error.code) throw error;
        throw failure("BAD_PARAMS", method + " was given a value that cannot be sent to something; pass only JSON values.");
      });
  }

  // Keys left undefined are left out: the engine reads a missing key as "not given".
  function given(params, values, keys) {
    keys.forEach(function (key) { if (values && values[key] !== undefined) params[key] = values[key]; });
    return params;
  }

  // A listener that throws must not stop the others; its error still reaches the page as uncaught, with its file
  // and line: reportError keeps them, where a throw from this injected script would reach the page as "Script error.".
  function tell(event, value) {
    listeners[event].slice().forEach(function (fn) {
      try { fn(value); } catch (error) {
        if (typeof reportError === "function") reportError(error); else setTimeout(function () { throw error; });
      }
    });
  }

  const something = {
    state: function () { return call("state", {}); },
    on: function (event, fn) {
      if (!Object.prototype.hasOwnProperty.call(listeners, event)) {
        throw failure("UNKNOWN_EVENT", "something.on takes \"change\" or \"granted\", not " + JSON.stringify(event) + ".");
      }
      if (typeof fn !== "function") throw failure("BAD_PARAMS", "something.on needs a function to call.");
      listeners[event].push(fn);
      return function () {
        const at = listeners[event].indexOf(fn);
        if (at >= 0) listeners[event].splice(at, 1);
      };
    },
    // Without `when` the engine holds the message for the next turn ("next", the default).
    send: function (agent, text, options) { return call("send", given({ agent: agent, text: text }, options, ["when"])); },
    interrupt: function (agent) { return call("interrupt", { agent: agent }); },
    set: function (agent, values) { return call("set", given({ agent: agent }, values, ["model", "mode", "effort"])); },
    launch: function (kind, options) { return call("launch", given({ kind: kind }, options, ["folder", "model", "mode", "effort"])); },
    resume: function (kind, threadId) { return call("resume", { kind: kind, thread: threadId }); },
    store: Object.freeze({
      get: function (path) { return call("store.get", { path: path }); },
      set: function (path, value) { return call("store.set", { path: path, value: value === undefined ? null : value }); },
    }),
    open: function (url) { return call("open", { url: url }); },
    // For the engine only: a new state, and new rights (a revocation reaches an open space this way).
    _push: function (state) { tell("change", state); },
    _granted: function (value) { granted = value; tell("granted", value); },
  };
  Object.defineProperty(something, "contract", { value: 1, enumerable: true });
  Object.defineProperty(something, "granted", { get: function () { return granted; }, enumerable: true });
  window.something = Object.freeze(something);
})();
