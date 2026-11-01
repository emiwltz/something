// What an exported space's HTML file runs in a browser, after something.js: there is no host, so every agent call stays
// refused with NO_HOST, and a page written to the guide hides what needs agents. Its memory works over the `data` the
// file carries, kept in this browser. A folder's other files, which the file carries too, become blob URLs: each `src`
// and `href` is rewritten as the parser adds it, and `fetch` answers for those paths. An image or a font named inside a
// stylesheet stays empty. Inside something it does nothing: the real bridge is there.
(function () {
  "use strict";
  const base = window.something, webkit = window.webkit;
  if (webkit && webkit.messageHandlers && webkit.messageHandlers.something) return;
  const exported = JSON.parse(document.getElementById("something-export").textContent);

  function failure(code, message) {
    const error = new Error(message);
    error.code = code;
    return error;
  }

  // The memory, with the rules of the engine's: paths of keys joined by "/", null removes, 5 MB at most.
  const place = "something-export:" + exported.name + ":" + exported.exported;
  let memory = exported.data || {};
  try {
    const kept = localStorage.getItem(place);
    if (kept) memory = JSON.parse(kept);
  } catch (error) { /* A browser that keeps nothing still shows the file's memory. */ }

  function keys(path) {
    if (typeof path !== "string" || path.split("/").includes("") && path !== "") {
      throw failure("BAD_PARAMS", JSON.stringify(path) + " is no path: a path is keys joined by /, for example settings/theme.");
    }
    return path === "" ? [] : path.split("/");
  }

  function put(object, path, value) {
    const key = path[0];
    const own = Object.prototype.hasOwnProperty.call(object, key);
    if (path.length === 1) {
      if (value === null) delete object[key]; else object[key] = value;
      return;
    }
    if (!own && value === null) return;
    if (!own) object[key] = {};
    const child = object[key];
    if (child === null || typeof child !== "object" || Array.isArray(child)) {
      throw failure("BAD_PARAMS", JSON.stringify(key) + " holds a value that is not an object, so nothing can be put inside it.");
    }
    put(child, path.slice(1), value);
  }

  function keep(next) {
    const text = JSON.stringify(next);
    if (new Blob([text]).size > 5000000) throw failure("STORE_FULL", "The memory would weigh more than the limit of 5 MB.");
    memory = next;
    try { localStorage.setItem(place, text); } catch (error) { /* It lasts as long as the page, then. */ }
  }

  const store = Object.freeze({
    get: function (path) {
      if (!stores()) return base.store.get(path);
      return new Promise(function (resolve) {
        const value = keys(path).reduce(function (held, key) {
          return held !== null && typeof held === "object" && !Array.isArray(held) && Object.prototype.hasOwnProperty.call(held, key) ? held[key] : null;
        }, memory);
        resolve(value === undefined ? null : JSON.parse(JSON.stringify(value)));
      });
    },
    set: function (path, value) {
      if (!stores()) return base.store.set(path, value);
      return new Promise(function (resolve) {
        const steps = keys(path), plain = value === undefined ? null : JSON.parse(JSON.stringify(value));
        if (steps.length === 0) {
          if (plain !== null && (typeof plain !== "object" || Array.isArray(plain))) {
            throw failure("BAD_PARAMS", "The whole memory is one JSON object: store.set(\"\", value) takes an object, or null to empty it.");
          }
          keep(plain || {});
        } else {
          const next = JSON.parse(JSON.stringify(memory));
          put(next, steps, plain);
          keep(next);
        }
        resolve(null);
      });
    },
  });

  // Read at each call: the declaration comes after this script, and before the page's own.
  function stores() {
    try {
      return JSON.parse(document.getElementById("something").textContent).rights.includes("store");
    } catch (error) { return false; }
  }

  window.something = Object.freeze(Object.create(base, {
    store: { value: store, enumerable: true },
    granted: { get: function () { return Object.assign({}, base.granted, { rights: stores() ? ["store"] : [] }); }, enumerable: true },
  }));

  const files = exported.files, made = {};
  if (Object.keys(files).length === 0) return;
  const types = {
    css: "text/css", js: "text/javascript", mjs: "text/javascript", html: "text/html", json: "application/json", svg: "image/svg+xml",
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", woff2: "font/woff2", woff: "font/woff",
    ttf: "font/ttf", otf: "font/otf", mp3: "audio/mpeg", wav: "audio/wav", mp4: "video/mp4", webm: "video/webm", wasm: "application/wasm",
  };

  // The file's path a page's address means, read as the space's own server reads it; undefined for any other address.
  function path(address) {
    const folder = document.baseURI.replace(/[^/]*$/, ""), relative = address.startsWith(folder) ? address.slice(folder.length) : address;
    try {
      const url = new URL(relative, "http://space.invalid/");
      const named = url.host === "space.invalid" ? decodeURIComponent(url.pathname.slice(1)) : undefined;
      return Object.prototype.hasOwnProperty.call(files, named) ? named : undefined;
    } catch (error) { return undefined; }
  }

  function blob(name) {
    if (!made[name]) {
      const type = types[name.split(".").pop().toLowerCase()] || "application/octet-stream";
      made[name] = new Blob([Uint8Array.from(atob(files[name]), function (c) { return c.charCodeAt(0); })], { type: type });
    }
    return made[name];
  }

  function rewrite(element, attribute) {
    const name = element.hasAttribute(attribute) ? path(element.getAttribute(attribute)) : undefined;
    if (name !== undefined) element.setAttribute(attribute, URL.createObjectURL(blob(name)));
  }

  function rewriteAll(element) {
    ["src", "href"].forEach(function (attribute) { rewrite(element, attribute); });
  }

  // Parsing stops at each script's end tag for these records, so a script's `src` is rewritten before it loads.
  new MutationObserver(function (records) {
    records.forEach(function (record) {
      if (record.type === "attributes") rewrite(record.target, record.attributeName);
      record.addedNodes.forEach(function (node) {
        if (node.nodeType !== 1) return;
        rewriteAll(node);
        node.querySelectorAll("[src], [href]").forEach(rewriteAll);
      });
    });
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["src", "href"] });

  const fetched = window.fetch;
  window.fetch = function (input, options) {
    const name = path(typeof input === "string" ? input : String(input && input.url || input));
    if (name === undefined) return fetched.call(window, input, options);
    return Promise.resolve(new Response(blob(name), { headers: { "Content-Type": blob(name).type } }));
  };
})();
