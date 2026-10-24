// The open space in a real WKWebView, never shown: nothing reaches the network, no space reads
// another's storage, the bridge answers the page and only the page, links go to the link window, the rights are
// asked once and remembered, and the window reloads when the space changes. Serialized: each test turns the run loop.
import AppKit
import Foundation
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-window-")) struct SpaceViewTests {
    init() {
        // WebKit's processes talk to an application; this one never shows in the Dock and never takes the focus.
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    /// Every way a page could reach a server, aimed at a listener on 127.0.0.1. The listener must see nothing.
    @Test func nothingReachesTheNetwork() async throws {
        let home = Home(prefix: "something-window-"), listener = try Listener()
        defer { home.remove(); listener.stop() }
        let base = "http://127.0.0.1:\(listener.port)"

        // The listener works, and WebKit without something's lock reaches it: zero hits below means something.
        let plain = WKWebViewConfiguration()
        plain.websiteDataStore = .nonPersistent()
        let control = WKWebView(frame: .zero, configuration: plain)
        control.loadHTMLString("<img src=\"\(base)/control\">", baseURL: nil)
        #expect(await wait(until: { listener.hits.count == 1 }), "the control did not reach the listener: \(listener.hits)")

        let ask = FakeAsk()
        // Every link is opened: three Cancels would stop its sheets before the last clicks.
        ask.link = true
        let window = try await home.window(try home.space("lockdown", """
            <!doctype html><html><head>
            <meta http-equiv="refresh" content="0;url=\(base)/refresh">
            <link rel="prefetch" href="\(base)/prefetch"><link rel="preconnect" href="\(base)">
            <link rel="stylesheet" href="\(base)/style.css">
            <style>body { background: url(\(base)/css-url); } @font-face { font-family: x; src: url(\(base)/font); }</style>
            <script src="\(base)/script.js"></script>
            </head><body style="font-family: x">x
            <img src="\(base)/img"><iframe src="\(base)/iframe"></iframe>
            <form id="form" action="\(base)/form" method="post"><input name="a" value="b"></form>
            <a id="link" href="\(base)/link">link</a><a id="blank" target="_blank" href="\(base)/blank">blank</a>
            <a id="real" href="\(base)/real-click" style="position: fixed; left: 0; top: 0; width: 200px; height: 200px; display: block">real</a>
            <a id="ping" href="#here" ping="\(base)/ping">ping</a>
            <link rel="preload" as="script" href="\(base)/preload"><link rel="modulepreload" href="\(base)/modulepreload">
            <link rel="dns-prefetch" href="\(base)"><style>@import url(\(base)/css-import);</style>
            <video src="\(base)/video"></video><audio src="\(base)/audio"></audio>
            <object data="\(base)/object"></object><embed src="\(base)/embed">
            <iframe id="framed" srcdoc="<a id='inner' href='\(base)/srcdoc-link'>inner</a>"></iframe>
            <div id="host"></div>
            <a id="dispatched" href="\(base)/dispatched">dispatched</a><a id="top" target="_top" href="\(base)/top-link">top</a>
            <a id="parent" target="_parent" href="\(base)/parent-link">parent</a>
            <map name="map"><area id="area" href="\(base)/area" shape="rect" coords="0,0,10,10"></map><img usemap="#map" src="data:,">
            <svg><a id="svg" href="\(base)/svg"><text y="10">svg</text></a></svg>
            <div><template shadowrootmode="closed"><a id="declared" href="\(base)/declarative">declared</a>
              <a id="declared-blank" target="_blank" href="\(base)/declarative-blank">declared</a>
              <img src="data:," onerror="const root = this.getRootNode(); root.getElementById('declared').click();
                root.getElementById('declared-blank').click(); window.declaredClicked = root !== document"></template></div>
            <div id="real-shadow" style="position: fixed; left: 300px; top: 0; width: 200px; height: 200px"></div>
            <div id="real-shadow-blank" style="position: fixed; left: 600px; top: 0; width: 200px; height: 200px"></div>
            <script>
              for (const [id, target, path] of [["real-shadow", "", "real-shadow"], ["real-shadow-blank", "_blank", "real-shadow-blank"]]) {
                const root = document.getElementById(id).attachShadow({ mode: "closed" });
                root.innerHTML = `<a target="${target}" href="\(base)/${path}" style="display: block; width: 200px; height: 200px">x</a>`;
              }
            </script>
            <script>
              const base = "\(base)";
              const work = (name) => `fetch("${base}/${name}-worker").catch(() => {});
                try { new WebSocket("ws://127.0.0.1:\(listener.port)/${name}-worker-socket"); } catch (e) {}`;
              const tries = [
                () => fetch(base + "/fetch"),
                () => fetch(base + "/fetch-no-cors", { mode: "no-cors" }),
                () => { const x = new XMLHttpRequest(); x.open("GET", base + "/xhr"); x.send(); },
                () => new WebSocket("ws://127.0.0.1:\(listener.port)/websocket"),
                () => new EventSource(base + "/eventsource"),
                () => navigator.sendBeacon(base + "/beacon", "invented"),
                () => window.open(base + "/window-open"),
                () => { const i = new Image(); i.src = base + "/image-object"; document.body.append(i); },
                () => new Worker(base + "/worker.js"),
                () => document.getElementById("form").submit(),
                () => document.getElementById("link").click(),
                () => document.getElementById("blank").click(),
                () => { location.href = base + "/location"; },
                () => import(base + "/import.js"),
                () => document.getElementById("ping").click(),
                () => new Worker(URL.createObjectURL(new Blob([work("blob")], { type: "text/javascript" }))),
                () => new Worker("data:text/javascript," + encodeURIComponent(work("data"))),
                () => { const a = document.createElement("a"); a.href = base + "/detached"; a.click(); },
                () => { const a = document.createElement("a"); a.href = base + "/detached-event"; a.dispatchEvent(new MouseEvent("click")); },
                () => { const a = document.createElement("area"); a.href = base + "/detached-area"; a.click(); },
                () => document.getElementById("dispatched").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true })),
                () => document.getElementById("area").click(),
                () => document.getElementById("svg").querySelector("text").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true })),
                () => document.getElementById("top").click(),
                () => document.getElementById("parent").click(),
                () => { top.location = base + "/top-location"; },
                () => { top.location.href = base + "/top-href"; },
                () => { parent.location.replace(base + "/parent-replace"); },
                () => window.open(base + "/top-open", "_top"),
                () => { const a = document.createElement("a"); a.href = base + "/detached-blank"; a.target = "_blank"; a.click(); },
                () => {
                  const root = document.getElementById("host").attachShadow({ mode: "closed" });
                  root.innerHTML = `<a href="${base}/shadow"><span>shadow</span></a><a target="_blank" href="${base}/shadow-blank">b</a>`;
                  root.querySelector("span").click();
                  root.querySelector("[target]").click();
                },
                () => {
                  // A frame of its own gives a page fresh prototypes, made before something's could be put in place.
                  const frame = document.createElement("iframe");
                  document.body.append(frame);
                  const a = frame.contentDocument.createElement("a");
                  a.href = base + "/fresh-frame";
                  frame.contentDocument.body.append(a);
                  frame.contentWindow.HTMLElement.prototype.click.call(a);
                  const b = document.createElement("a");
                  b.href = base + "/fresh-prototype";
                  frame.contentWindow.HTMLElement.prototype.click.call(b);
                  window.freshClicked = true;
                },
                () => {
                  const frame = document.getElementById("framed");
                  const inner = () => frame.contentDocument && frame.contentDocument.getElementById("inner");
                  const go = () => { inner().click(); window.innerClicked = true; };
                  if (inner()) go(); else frame.addEventListener("load", go);
                },
              ];
              for (const attempt of tries) { try { const p = attempt(); if (p && p.catch) p.catch(() => {}); } catch (e) {} }
              try { eval("1"); window.evaluated = true; } catch (error) { window.evaluated = false; }
              // What a space may load still loads: its own file and an inline image.
              const dot = new Image();
              dot.src = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";
              Promise.all([fetch(location.href).then((r) => r.ok), dot.decode().then(() => dot.naturalWidth === 1)])
                .then((own) => { window.own = own; window.done = true; }, () => { window.own = "failed"; window.done = true; });
            </script></body></html>
            """), ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "return window.done") as? Bool == true, "the page did not run its tries")
        #expect(try await run(window, "return window.own") as? [Bool] == [true, true], "the space's own loads failed")
        #expect(try await run(window, "return window.evaluated") as? Bool == false, "eval is refused, as the guide says")
        #expect(try await run(window, "return window.declaredClicked") as? Bool == true, "the declarative shadow root's script ran")
        // Real clicks of the mouse, sent to the view of a window that is never shown: on a link of the page, and on a
        // link inside a shadow root the page made closed.
        let offscreen = Offscreen(window.web)
        // Each click is sent until the page saw it, then its link waited for: a busy runner loses some.
        for (x, path) in [(50.0, "/real-click"), (400, "/real-shadow")] {
            #expect(try await offscreen.click(x: x, y: 590, on: window), "the page never saw the click on \(path)")
            await wait(30) { ask.links.contains { $0.path == path } }
        }
        // The frames' clicks are waited for; then anything that would reach the network is given 3 s more.
        for _ in 0..<600 where try await run(window, "return window.innerClicked && window.freshClicked") as? Bool != true { await wait(0.05) }
        await wait(3)
        #expect(try await run(window, "return [window.innerClicked, window.freshClicked]") as? [Bool] == [true, true])
        #expect(listener.hits.count == 1, "reached: \(listener.hits.dropFirst().joined(separator: " | "))")
        // A clicked link goes to the link window instead, which the person answered here, one in a closed shadow root
        // included: a script's shadow root is open to something's guard.
        #expect(ask.links.map(\.path) == ["/link", "/blank", "/dispatched", "/area", "/svg", "/top-link", "/parent-link", "/real-click",
                                         "/real-shadow"])
        #expect(window.web.url == Scheme.shell, "the app's page is still the main frame")
        #expect(try await run(window, "return location.origin + location.pathname") as? String == "something://space/lockdown.html")
    }

    /// A shadow root a script makes is open whatever the page asked (Lockdown.activationScript), so a real click on a
    /// link inside one goes to the link window, new-window links included, and nothing reaches the network. The gap
    /// left (README, "No network for spaces"): a closed shadow root written in the HTML itself, which no script makes,
    /// where a real click on a new-window link (target="_blank") makes WebKit open one connection to the link's server
    /// before the sandbox refuses the window. Marked as known: when WebKit stops doing it, Swift Testing reports that
    /// the known issue was not recorded, and this test and the README's paragraph are updated.
    @Test func aLinkInAShadowRootGoesToTheLinkWindow() async throws {
        let home = Home(prefix: "something-window-"), listener = try Listener(), ask = FakeAsk()
        defer { home.remove(); listener.stop() }
        let base = "http://127.0.0.1:\(listener.port)"
        let window = try await home.window(try home.space("gap", page(nil, """
            <div id="host" style="position: fixed; left: 0; top: 0; width: 450px; height: 640px"></div>
            <div><template shadowrootmode="closed">
              <a target="_blank" href="\(base)/declared" style="position: fixed; left: 450px; top: 0; width: 450px; height: 640px">gap</a>
            </template></div>
            <script>
              const root = document.getElementById("host").attachShadow({ mode: "closed" });
              root.innerHTML = `<a target="_blank" href="\(base)/scripted" style="position: fixed; left: 0; top: 0; width: 450px; height: 640px">x</a>`;
              window.done = true;
            </script>
            """)), ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        let offscreen = Offscreen(window.web)
        // Sent until the page saw it, then waited for, not timed: a busy runner loses clicks, or takes seconds.
        #expect(try await offscreen.click(x: 200, y: 320, on: window), "the page never saw the click")
        await wait(30, until: { !ask.links.isEmpty })
        await wait(1)
        #expect(ask.links.map(\.path) == ["/scripted"])
        #expect(listener.hits.isEmpty, "reached: \(listener.hits)")
        #expect(try await offscreen.click(x: 650, y: 320, on: window), "the page never saw the second click")
        await wait(15, until: { !listener.hits.isEmpty })
        // Intermittent: WebKit opens that connection ahead of the click's handling, and a busy runner may not get to it.
        withKnownIssue("WebKit connects to the server of a new-window link in a closed shadow root of the HTML", isIntermittent: true) {
            #expect(listener.hits.isEmpty, "reached: \(listener.hits)")
        }
    }

    /// The agents a space launched outlive its window: the app keeps them by the space's name, so that the space,
    /// closed and opened again, still sees and drives them, and another space does not. A space made again under that
    /// name after its answers were forgotten is a new space: it sees none of them. The launch goes through the bridge's
    /// host, with a fake `claude` that only reads its input, on the throwaway engine's PATH.
    @Test func launchedAgentsOutliveTheWindow() async throws {
        let home = Home(prefix: "something-window-"), launches = Launches(), rules = try await Lockdown.ruleList(), ask = FakeAsk()
        defer { home.remove() }
        let bin = home.root.appendingPathComponent("bin"), shop = home.root.appendingPathComponent("code/shop")
        for folder in [bin, shop] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let claude = bin.appendingPathComponent("claude")
        try "#!/bin/sh\nwhile IFS= read -r line; do :; done\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        ask.answer = { RightsAnswer(allowed: $0, refused: [], folder: shop.path, remap: [:]) }
        let engine = home.engine()
        let declared = #"{"contract": 1, "title": "Board", "rights": ["launch:claude"], "folder": "~/code/shop"}"#
        let board = try home.space("board", page(declared, "")), other = try home.space("other", page(nil, ""))
        func opened(_ space: Space) throws -> SpaceView {
            let window = try SpaceView(space: space, places: home.places, engine: engine, ask: ask, share: Home.share, rules: rules,
                                         launches: launches)
            window.load()
            return window
        }
        let first = try opened(board)
        let id = try first.launch("claude", folder: shop.path, model: nil, mode: nil, effort: nil)
        first.close()
        let again = try opened(board), elsewhere = try opened(other)
        #expect(Rights.visible(engine.state, again.granted, launched: again.launched).agents.map(\.id) == [id])
        #expect(Rights.visible(engine.state, elsewhere.granted, launched: elsewhere.launched).agents.isEmpty)
        again.close()
        elsewhere.close()

        try Library.forget("board", in: home.places, recycle: { _ in Issue.record("no versions to trash") })
        let new = try opened(board)
        defer { new.close() }
        #expect(new.launched.isEmpty)
        #expect(Rights.visible(engine.state, new.granted, launched: new.launched).agents.isEmpty)
        var stopped = false
        engine.stopAll(within: 6) { stopped = true }
        #expect(await wait(until: { stopped }))
    }

    /// Every space has the same origin, something://space, so each window has its own data store. Two spaces open at
    /// the same time share nothing: no storage, no cookie, no database, no cache, no message between windows.
    @Test func noSpaceReadsAnothersStorage() async throws {
        let home = Home(prefix: "something-window-"), ask = FakeAsk()
        defer { home.remove() }
        let listening = "<script>window.heard = []; new BroadcastChannel('kept').onmessage = (e) => heard.push(e.data); window.done = true</script>"
        let a = try await home.window(try home.space("space-a", page(nil, listening)), ask)
        defer { a.close() }
        let b = try await home.window(try home.space("space-b", page(nil, listening)))
        defer { b.close() }
        a.open()
        b.open()
        try await ready(a)
        try await ready(b)
        #expect(ask.questions.isEmpty, "a space that declares no right is asked nothing")
        // The database is read back by its key, and looked for in b by opening it: on macOS 15, indexedDB.databases()
        // gave an empty list right after a database was written (seen on CI; most likely it lists only what a store
        // keeps on disk, and these stores keep nothing), so a count of it would prove nothing there.
        let stored = try await run(a, """
            localStorage.setItem("kept", "from a");
            document.cookie = "kept=from-a";
            const database = await new Promise((done, failed) => {
              const opening = indexedDB.open("kept");
              opening.onupgradeneeded = () => opening.result.createObjectStore("store");
              opening.onsuccess = () => done(opening.result);
              opening.onerror = failed;
            });
            await new Promise((done, failed) => {
              const writing = database.transaction("store", "readwrite");
              writing.objectStore("store").put("from a", "key");
              writing.oncomplete = done;
              writing.onerror = failed;
            });
            const kept = await new Promise((done, failed) => {
              const reading = database.transaction("store").objectStore("store").get("key");
              reading.onsuccess = () => done(reading.result);
              reading.onerror = failed;
            });
            if (self.caches) await (await caches.open("kept")).put("https://example.com/kept", new Response("from a"));
            new BroadcastChannel("kept").postMessage("from a");
            return [localStorage.getItem("kept"), kept, document.cookie.includes("kept"), self.caches ? await caches.has("kept") : null]
            """)
        // a keeps what it stored, so b's empty stores mean something. The cookie is the exception: WebKit keeps none
        // for the something scheme (seen on macOS 26), so no space has one to share. Should WebKit start keeping
        // them, this fails, and b's cookie check below starts to prove isolation.
        #expect(stored as? [AnyHashable] == ["from a", "from a", false, true], "\(String(describing: stored))")
        // The message is waited for: on a slow Mac its delivery may take longer than any fixed pause.
        var heard: [String]?
        let end = Date().addingTimeInterval(30)
        while heard?.isEmpty != false, Date() < end {
            heard = try await run(a, "return heard") as? [String]
            await wait(0.05)
        }
        #expect(heard == ["from a"], "a message reaches the space's own listener")
        #expect(try await run(b, """
            const found = await new Promise((done, failed) => {
              const opening = indexedDB.open("kept");
              let made = false;
              opening.onupgradeneeded = (event) => made = event.oldVersion === 0;
              opening.onsuccess = () => {
                const stores = opening.result.objectStoreNames.length;
                opening.result.close();
                done(!made || stores > 0);
              };
              opening.onerror = failed;
            });
            return [localStorage.getItem("kept"), document.cookie.includes("kept"), found,
                    self.caches ? await caches.has("kept") : false, heard.length]
            """) as? [AnyHashable] == [NSNull(), false, false, false, 0])

        // Storage ends with the window: the same space, opened again, starts empty.
        a.close()
        let again = try await home.window(try #require(Spaces(root: home.places.spaces).named("space-a")))
        defer { again.close() }
        again.open()
        try await ready(again)
        #expect(try await run(again, "return localStorage.getItem('kept')") == nil)
    }

    @Test func theBridgeAnswersThePageAndOnlyThePage() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let ask = FakeAsk()
        let window = try await home.window(try home.space("bridge", page(#"{"contract": 1, "rights": ["state", "store"]}"#, """
            <script>window.first = something.granted.rights.join(","); window.done = true</script>
            <iframe srcdoc="<script>webkit.messageHandlers.something.postMessage({contract: 1, id: 1, method: 'state', params: {}})
              .then(() => parent.framed = 'answered', (e) => parent.framed = 'refused')</script>"></iframe>
            <iframe id="own" src="bridge.html"></iframe><iframe id="opened"></iframe><iframe id="named" name="named"></iframe>
            <a id="into" href="bridge.html" target="named">into</a>
            <script>
              document.getElementById("into").click();
              // A frame that the space writes itself takes the space's address; it is still not the space's frame.
              const opened = document.getElementById("opened").contentDocument;
              opened.open();
              opened.write("<script>webkit.messageHandlers.something.postMessage({contract: 1, id: 1, method: 'state', params: {}})" +
                ".then(() => parent.opened = 'answered', (e) => parent.opened = 'refused')<\\/script>");
              opened.close();
            </script>
            """)), ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "return window.first") as? String == "state,store", "granted is set before the page's scripts")
        #expect(try await run(window, "return something.contract") as? Int == 1)
        #expect(try await run(window, "return (await something.state()).contract") as? Int == 1)
        #expect(try await run(window, "await something.store.set('a/b', 2); return await something.store.get('a')") as? [String: Int] == ["b": 2])
        #expect(FileManager.default.fileExists(atPath: home.places.data.appendingPathComponent("bridge.json").path))
        #expect(try await run(window, "try { await something.send('a1', 'invented') } catch (e) { return e.code }") as? String == "RIGHT_NOT_GRANTED")
        var framed: String?
        for _ in 0..<600 where framed == nil {
            framed = try await run(window, "return window.framed ?? null") as? String
            await wait(0.05)
        }
        #expect(framed == "refused", "a frame inside the space is not answered")
        #expect(try await run(window, "return window.opened ?? null") as? String == "refused", "nor a frame the space wrote")
        #expect(try await run(window, "return document.getElementById('own').contentWindow.location.href") as? String == "about:blank",
                "a frame inside the space never holds a file of the space")
        #expect(try await run(window, "return document.getElementById('named').contentWindow.location.href") as? String == "about:blank",
                "not even through a link that targets it")
        #expect(try await run(window, "try { return parent.document.title } catch (e) { return e.name }") as? String == "SecurityError",
                "the space cannot reach the app's page")
        #expect(try await run(window, "return typeof something") as? String == "object")

        // Links: one window at a time, and none after three Cancels until the page reloads. Each one is journaled.
        // While the link window is open, its modal loop turns the run loop: the page's second call is answered then.
        ask.during = { _ in
            window.web.evaluateJavaScript("something.open('https://example.com/b').then((v) => window.nested = v, (e) => window.nested = e.code)",
                                          in: window.frame, in: .page)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        #expect(try await run(window, "return await something.open('https://example.com/a')") as? Bool == false)
        #expect(ask.links == [URL(string: "https://example.com/a")!])
        #expect(try await run(window, "return window.nested") as? String == "BUSY")
        ask.during = nil
        for link in ["c", "d", "e"] {
            #expect(try await run(window, "return await something.open('https://example.com/\(link)')") as? Bool == false)
        }
        #expect(ask.links.count == 3)
        let journal = try Journal(folder: home.places.journals).last(10, space: "bridge")
        // The second call ends first, while the first one waits on the person.
        #expect(journal.map(\.result) == ["RIGHT_NOT_GRANTED", "BUSY", "ok", "ok", "ok", "ok"])
        // A real reload asks again.
        let before = try #require(window.frame)
        window.load()
        #expect(await wait(until: { window.frame != nil && window.frame !== before }))
        try await ready(window)
        #expect(try await run(window, "return await something.open('https://example.com/f')") as? Bool == false)
        #expect(ask.links.count == 4)
    }

    @Test func aModeThatLowersAskingIsConfirmed() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let ask = FakeAsk()
        let window = try await home.window(try home.space("modes", page(nil, "")), ask)
        defer { window.close() }
        #expect(try window.confirms(mode: "default", kind: "claude", folder: "/Users/example/code/shop"))
        #expect(try !window.confirms(mode: "acceptEdits", kind: "claude", folder: "/Users/example/code/shop"))
        ask.lowers = true
        #expect(try window.confirms(mode: "never", kind: "codex", folder: nil))
        #expect(try window.confirms(mode: "plan", kind: "opencode", folder: nil), "OpenCode's modes are its agents")
        #expect(ask.modes == ["acceptEdits", "never"])
        // Never offered, even with a click: a mode that never asks, and any mode something does not know.
        for (mode, kind) in [("bypassPermissions", "claude"), ("acceptedits", "claude"), ("granular", "codex")] {
            do {
                _ = try window.confirms(mode: mode, kind: kind, folder: nil)
                Issue.record("\(mode) was offered")
            } catch { #expect((error as? CodedError)?.code == "VALUE_NOT_OFFERED") }
        }
        #expect(ask.modes.count == 2)
    }

    /// OpenCode launches with build or plan: an agent the person wrote is refused before the person is asked.
    @Test func aLaunchThatCannotHappenAsksNothing() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let shop = home.root.appendingPathComponent("code/shop")
        try FileManager.default.createDirectory(at: shop, withIntermediateDirectories: true)
        let ask = FakeAsk()
        ask.lowers = true
        ask.answer = { RightsAnswer(allowed: $0, refused: [], folder: shop.path, remap: [:]) }
        let declared = #"{"contract": 1, "title": "Launcher", "rights": ["launch:opencode"], "folder": "~/code/shop"}"#
        let window = try await home.window(try home.space("launcher", page(declared, "<script>window.done = true</script>")), ask)
        defer { window.close() }
        window.open()
        try await ready(window)
        let code = try await run(window, "try { await something.launch('opencode', {mode: 'my-agent'}); return 'ok' } catch (e) { return e.code }")
        #expect(code as? String == "VALUE_NOT_OFFERED")
        #expect(ask.modes.isEmpty)
    }

    /// The rights sheet says that pi never asks before it acts, for launch:pi and for launch, which covers pi.
    @Test func theRightsSheetSaysThatPiNeverAsks() {
        #expect(Ask.words(for: "launch:pi") == "Start pi in a folder you choose. pi runs commands and edits files without asking you first")
        #expect(Ask.words(for: "launch") == "Start agents in a folder you choose. Some of them run commands and edit files without asking you first: pi, OMP by default, and Amp")
        #expect(!Ask.words(for: "launch:claude").contains("without asking"))
    }

    /// granted.limits is the guide's table "What each kind can do", as the contract's own fixtures give it.
    @Test func theLimitsAreTheContracts() throws {
        let bridge = Home.share.appendingPathComponent("contract/bridge")
        let cases = try FileManager.default.contentsOfDirectory(at: bridge, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        #expect(!cases.isEmpty)
        for file in cases {
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let limits = (fixture?["granted"] as? [String: Any])?["limits"] as? [String: [String]]
            #expect(limits == Registry.app.limits, "\(file.lastPathComponent)")
        }
    }

    /// The rights sheet: one switch per right, all off; Allow greyed until one is on; the switches answer which are
    /// allowed and which refused; Return and Escape press Don't Allow, which grants nothing (NativeAsk returns nil).
    @Test func theRightsSheetStartsOffAndAllowsOnlyWhatIsOn() throws {
        let question = RightsQuestion(space: "Review", description: nil, rights: ["state", "send:codex", "store"], scope: nil,
                                      missing: [], folder: nil, page: "/Users/example/something/spaces/review.html")
        let (sheet, answer) = Ask.rights(question, home: "/Users/example")
        let switches = Self.switches(sheet.contentView)
        #expect(switches.map(\.state) == [.off, .off, .off] && switches.map { $0.accessibilityLabel() } == ["See your agents", "Write to your Codex agents", "Remember things"])
        #expect(sheet.buttons.map(\.title) == ["Don't Allow", "Allow"] && sheet.buttons.map(\.role) == [.cancel, .primary])
        #expect(!sheet.buttons[1].isEnabled, "Allow waits for a switch")
        #expect(answer() == RightsAnswer(allowed: [], refused: ["state", "send:codex", "store"], folder: nil, remap: [:]))
        switches[0].performClick(nil)
        switches[2].performClick(nil)
        #expect(sheet.buttons[1].isEnabled)
        #expect(answer() == RightsAnswer(allowed: ["state", "store"], refused: ["send:codex"], folder: nil, remap: [:]))
        switches[0].performClick(nil)
        switches[2].performClick(nil)
        #expect(!sheet.buttons[1].isEnabled, "all off again")
        sheet.buttons[1].performClick(nil)
        #expect(sheet.chosen == nil, "a greyed Allow cannot be pressed")
        // Escape presses Don't Allow, so nothing is granted, even with a switch on; Return too, as it holds the focus.
        switches[1].performClick(nil)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                   characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(sheet.performKeyEquivalent(with: escape) && sheet.chosen == .cancel)
        let other = Ask.rights(question).sheet
        #expect(other.firstResponder === other.buttons[0])
        Self.switches(other.contentView)[0].performClick(nil)
        other.keyDown(with: try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                          characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
        #expect(other.chosen == .cancel)
        // The fine print says what the space does not ask for, among all it declares.
        #expect(Ask.fine(question) == "It does not ask to start agents. Each right starts off; change it later in its Info.")
        var all = question
        all.declared = ["state", "send", "launch:pi", "store"]
        #expect(Ask.fine(all) == "Each right starts off; change it later in its Info.")
    }

    static func switches(_ view: NSView?) -> [SheetSwitch] {
        (view?.subviews ?? []).flatMap { ($0 as? SheetSwitch).map { [$0] } ?? switches($0) }
    }

    @Test func rightsAreAskedOnceAndRemembered() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let shop = home.root.appendingPathComponent("code/shop")
        try FileManager.default.createDirectory(at: shop, withIntermediateDirectories: true)
        let declared = #"{"contract": 1, "title": "Review", "rights": ["state", "store", "launch:codex"], "agents": {"folders": ["~/code/shop", "~/code/blog"]}, "folder": "~/code/shop"}"#
        let ask = FakeAsk()
        ask.answer = { _ in RightsAnswer(allowed: ["state", "launch:codex"], refused: ["store"], folder: shop.path,
                                         remap: ["~/code/blog": "/Users/example/blog"]) }
        let space = try home.space("review", page(declared, "<script>window.done = true</script>"))
        let first = try await home.window(space, ask)
        defer { first.close() }
        first.open()
        try await ready(first)
        first.close()
        #expect(ask.questions == [RightsQuestion(space: "Review", description: nil, rights: ["state", "store", "launch:codex"],
                                                 scope: .folders(["~/code/shop", "~/code/blog"]), missing: ["~/code/blog"],
                                                 folder: FolderQuestion(declared: "~/code/shop", found: shop.path),
                                                 page: space.location.path, declared: ["state", "store", "launch:codex"])])
        #expect(first.granted.rights == ["state", "launch:codex"] && first.granted.refused == ["store"])
        #expect(first.granted.folder == shop.path)
        #expect(first.granted.agents == .folders([shop.path, "/Users/example/blog"]))
        let grant = try #require(try AppFile.read(home.places.grants).spaces["review"])
        #expect(grant.granted == ["state", "launch:codex"] && grant.remap == ["~/code/blog": "/Users/example/blog"])

        // Opened again: nothing new to ask. A right added to the declaration is the only thing asked next.
        let second = try await home.window(space, ask)
        defer { second.close() }
        second.open()
        #expect(ask.questions.count == 1)
        second.close()
        try page(declared.replacingOccurrences(of: #""store","#, with: #""store", "send:codex","#), "")
            .write(to: space.location, atomically: true, encoding: .utf8)
        let third = try await home.window(space, ask)
        defer { third.close() }
        third.open()
        #expect(ask.questions.last?.rights == ["send:codex"])
        #expect(ask.questions.last?.folder == nil && ask.questions.last?.scope == nil)
    }

    /// The scope is shown whenever `state` is asked, even when it was answered earlier with another right.
    @Test func stateAddedLaterShowsItsScope() async throws {
        let home = Home(prefix: "something-window-"), ask = FakeAsk()
        defer { home.remove() }
        let space = try home.space("later", page(#"{"contract": 1, "rights": ["store"], "agents": {"see": "all"}}"#, ""))
        let first = try await home.window(space, ask)
        first.open()
        first.close()
        #expect(ask.questions.last?.scope == nil, "without state, the scope shows nothing")
        try page(#"{"contract": 1, "rights": ["store", "state"], "agents": {"see": "all"}}"#, "").write(to: space.location, atomically: true, encoding: .utf8)
        let second = try await home.window(space, ask)
        defer { second.close() }
        second.open()
        #expect(ask.questions.last?.rights == ["state"] && ask.questions.last?.scope == .all)
    }

    /// The stamp that reloads a space follows each visible file of a folder, an image as much as the page, and stops
    /// its walk at `watched` entries: a space that holds a whole project does not keep the Mac busy each second.
    @Test func theStampFollowsEveryVisibleFileWithinItsLimit() throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let board = home.places.spaces.appendingPathComponent("board")
        for (path, text) in [("index.html", "<p>Invented.</p>"), ("img/logo.svg", "<svg/>"), (".notes", "hidden"), (".cache/big", "hidden")] {
            let file = board.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        let space = try #require(Spaces(root: home.places.spaces).named("board"))
        let set = { (path: String, seconds: TimeInterval) in
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)],
                                                  ofItemAtPath: board.appendingPathComponent(path).path)
        }
        try set("index.html", 1_800_000_000)
        try set("img/logo.svg", 1_800_000_100)
        try set(".notes", 1_900_000_000)
        try set(".cache/big", 1_900_000_000)
        #expect(SpaceView.stamp(of: space) == Date(timeIntervalSince1970: 1_800_000_100))
        try set("img/logo.svg", 1_800_000_200)
        #expect(SpaceView.stamp(of: space) == Date(timeIntervalSince1970: 1_800_000_200))

        let many = board.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<SpaceView.watched { FileManager.default.createFile(atPath: many.appendingPathComponent("\(index)").path, contents: nil) }
        let start = Date()
        #expect(SpaceView.stamp(of: space) != nil)
        #expect(Date().timeIntervalSince(start) < 1, "the walk stops at its limit")
    }

    @Test func aGrantsFileThatDoesNotReadIsLeftAndSaid() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        try "{ not json".write(to: home.places.grants, atomically: true, encoding: .utf8)
        let ask = FakeAsk()
        let window = try await home.window(try home.space("broken", page(#"{"contract": 1, "rights": ["state"]}"#, "")), ask)
        defer { window.close() }
        window.open()
        #expect(ask.told.count == 1 && ask.questions.isEmpty)
        #expect(window.granted.rights.isEmpty)
        #expect(try String(contentsOf: home.places.grants, encoding: .utf8) == "{ not json")
    }

    /// A reload that something did not start (WebKit's Reload, a restart after the web content process ended) gives
    /// the app's page a new frame: it is taken for the space, and pushes reach it.
    @Test func aReloadByWebKitFindsTheSpaceAgain() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let window = try await home.window(try home.space("again", page(nil, """
            <script>window.changes = 0; something.on("change", () => window.changes += 1); window.done = true</script>
            """)))
        defer { window.close() }
        window.open()
        try await ready(window)
        let before = try #require(window.frame)
        window.web.reload()
        #expect(await wait(until: { window.frame != nil && window.frame !== before }))
        try await ready(window)
        #expect(try await run(window, "return window.done === true && window.changes === 0") as? Bool == true)
        window.push()
        for _ in 0..<600 where try await run(window, "return window.changes") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window, "return window.changes") as? Int == 1)
    }

    @Test func theWindowReloadsWhenTheSpaceChanges() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let space = try home.space("live", page(#"{"contract": 2}"#, "<p id='word'>one</p>"))
        let window = try await home.window(space)
        defer { window.close() }
        window.open()
        #expect(window.blocked.map(\.code) == ["CONTRACT_TOO_NEW"])
        try page(#"{"contract": 1}"#, "<p id='word'>two</p><script>window.done = true</script>").write(to: space.location, atomically: true, encoding: .utf8)
        // The file system keeps seconds; a date in the future makes the change visible at once.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: space.location.path)
        #expect(await wait(until: { window.blocked.isEmpty }))
        try await ready(window)
        #expect(try await run(window, "return document.getElementById('word').textContent") as? String == "two")

        // Blocked again: the page the person no longer sees stops running.
        try page(#"{"contract": 2}"#, "<p id='word'>three</p>").write(to: space.location, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: space.location.path)
        #expect(await wait(until: { !window.blocked.isEmpty }))
        #expect(await wait(until: { !window.web.isLoading && window.web.url?.path == "/.blocked" }))
        #expect(try await run(window, "return document.getElementById('word') === null && window.done === undefined") as? Bool == true)
    }

    /// A reload keeps where the person scrolled the page to, read and given back from something's world; a reload
    /// that brings another page of the space starts at its top, and the page's own world sees no handler.
    @Test func aReloadKeepsTheScroll() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let tall = "<div style='height: 4000px'>tall</div><script>window.done = true</script>"
        let space = try home.space("tall", page(nil, tall))
        let window = try await home.window(space)
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "return window.webkit?.messageHandlers?.scrolled === undefined") as? Bool == true)
        _ = try await run(window, "scrollTo(0, 900); return 0")
        #expect(await wait(until: { window.scrolled?.y == 900 }), "the scroll was not said: \(String(describing: window.scrolled))")
        try page(nil, "<p>changed</p>" + tall).write(to: space.location, atomically: true, encoding: .utf8)
        window.load()
        try await ready(window)
        for _ in 0..<100 where try await run(window, "return scrollY") as? Double != 900 { await wait(0.05) }
        #expect(try await run(window, "return [scrollY, document.body.textContent.startsWith('changed')]") as? [AnyHashable] == [900, true])
        // Another page of the space is not where the last one was read.
        #expect(SpaceView.scrollScript(back: ("/other.html", 0, 900)).contains(#"["/other.html", 0.0, 900.0]"#))
    }

    /// A page whose process ends is said stopped; after two stops a changed file no longer reloads it, until the
    /// person's Reload. Ask to Fix names only the title, the file and something's own sentence.
    @Test func aPageThatStopsTwiceWaitsForReload() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let space = try home.space("crash", page(nil, "<title>Crash</title><script>window.done = true</script>"))
        let window = try await home.window(space)
        defer { window.close() }
        var shown = 0
        window.loaded = { shown += 1 }
        window.open()
        try await ready(window)
        let loads = window.loads
        window.webViewWebContentProcessDidTerminate(window.web)
        #expect(window.stopped && !window.paused && window.stops.count == 1 && window.frame == nil && shown == 2)
        func change(_ seconds: TimeInterval) throws {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(seconds)], ofItemAtPath: space.location.path)
        }
        // Once: a changed file still reloads it, the fix the assistant writes.
        try change(5)
        #expect(await wait(until: { window.loads == loads + 1 }))
        #expect(!window.stopped)
        try await ready(window)
        window.webViewWebContentProcessDidTerminate(window.web)
        window.webViewWebContentProcessDidTerminate(window.web)
        #expect(window.stopped && window.paused && window.stops.count == 3)
        try change(10)
        await wait(2.5)
        #expect(window.loads == loads + 1 && window.stopped, "a page that stopped twice is not reloaded by the watch")
        window.load()
        #expect(!window.stopped && !window.paused)
        try await ready(window)
        let fault = Stopped.fault(window)
        #expect(fault == AssistantModel.Fault(title: "crash", name: "crash.html", codes: ["STOPPED"]))
        #expect(AssistantModel.fixing(fault) == "The page of the space “crash” (crash.html) stopped responding. Find why and fix it.")
        let (said, when) = Stopped.words([Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 60), Date(timeIntervalSince1970: 120)],
                                         file: "crash.html", calendar: { var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt; return utc }(),
                                         hours: Locale(identifier: "en_GB"))
        #expect(said == "It stopped 3 times. something won't reload it again until you ask." && when == "crash.html · stopped at 00:01 and 00:02")
    }

    /// A page's uncaught errors: the codes are kept, and the first one's line, cut to one line, for the strip's quote
    /// alone; the page cannot post to "fault" itself, and Ask to Fix says only the codes.
    @Test func theFirstErrorIsShownAsAQuoteAndOnlyItsCodeIsSent() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let html = page(nil, """
            <script>
            try { webkit.messageHandlers.fault.postMessage({code: "SCRIPT_ERROR", message: "forged"}); window.forged = "sent"; } catch (_) { window.forged = "refused"; }
            setTimeout(() => { throw new TypeError("Ask me first\\nand a second line"); }, 0);
            setTimeout(() => { throw new Error("later"); }, 40);
            setTimeout(() => { window.done = true; }, 120);
            </script>
            """)
        let thrown = html.components(separatedBy: "\n").firstIndex { $0.contains("Ask me first") }.map { $0 + 1 }
        let window = try await home.window(try home.space("faults", html))
        defer { window.close() }
        window.open()
        try await ready(window)
        #expect(try await run(window, "return window.forged") as? String == "refused")
        #expect(window.faults == ["SCRIPT_ERROR"])
        let line = try #require(window.firstError)
        #expect(line == "TypeError: Ask me first · faults.html, line \(try #require(thrown))")
        // The strip: something's words, and the page's only inside the quote.
        let model = AssistantModel(engine: home.engine(), places: home.places)
        let strip = try #require(ScriptError(window, assistant: model))
        #expect(strip.quote.stringValue == "“\(line)”")
        #expect(PanelsTests.texts(strip).filter { $0.contains("Ask me") } == [strip.quote.stringValue])
        #expect(strip.fix.title == "Ask to Fix" && strip.accessibilityLabel() == "Script error")
        #expect(!AssistantModel.fixing(AssistantModel.Fault(title: window.title, name: "faults", codes: window.faults)).contains("Ask me"))
        // It pushes the page down by its height; closed, it stays closed until the next load.
        window.show(strip: strip)
        #expect(window.web.frame.height == window.area.bounds.height - ScriptError.height && strip.frame.maxY == window.area.bounds.height)
        strip.closeNow()
        #expect(window.dismissed && strip.superview == nil && window.web.frame == window.area.bounds)
        #expect(ScriptError(window, assistant: model) == nil)
        window.load()
        #expect(!window.dismissed && window.firstError == nil && window.faults.isEmpty)
    }

    @Test func anErrorLineIsOneLineOfAtMostTwoHundredCharacters() {
        #expect(ScriptError.line("TypeError: x\nmore", file: "brief.html", line: "142") == "TypeError: x · brief.html, line 142")
        #expect(ScriptError.line("Error: y", file: "", line: "0") == "Error: y")
        #expect(ScriptError.line("\n") == nil)
        let long = ScriptError.line(String(repeating: "a", count: 500))
        #expect(long?.count == 200 && long?.hasSuffix("…") == true)
    }

    /// Point mode asks the page from something's world only: a part is found where the page's own functions lie, by a
    /// path of standard tags and :nth-of-type, a small thing grown to its first ancestor of 40x24, a custom element
    /// passed over for its standard parent. The page's world sees no pointing function and hears no click of point
    /// mode; the wheel scrolls the page, or the box under it that scrolls, and the frames follow, a reload too.
    @Test func pointingFindsStandardPartsAndKeepsThePageOut() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let body = """
            <style>body { margin: 0 } td { width: 120px; height: 40px }</style>
            <div class="hero" id="hero" style="position: relative; height: 100px"><span class="tiny" style="position: absolute; left: 300px; top: 40px">x</span></div>
            <table class="data" style="margin: 20px"><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>
            <section><my-card style="display: block; height: 80px"><p class="inner">inside</p></my-card></section>
            <div class="pane" style="height: 60px; overflow-y: auto"><div style="height: 400px">long</div></div>
            <div style="height: 3000px"></div>
            <script>
              addEventListener("click", () => window.clicks = (window.clicks ?? 0) + 1, true);
              Document.prototype.elementFromPoint = function () { window.spied = true; return null; };
              Element.prototype.getBoundingClientRect = function () { window.spied = true; return new DOMRect(0, 0, 1, 1); };
              window.done = true;
            </script>
            """
        let space = try home.space("parts", page(nil, body))
        let window = try await home.window(space)
        defer { window.close() }
        let offscreen = Offscreen(window.area)
        window.open()
        try await ready(window)
        let frame = try #require(window.frame)
        func center(_ selector: String) async throws -> CGPoint {
            let box = try await window.web.callAsyncJavaScript("const b = document.querySelector(s).getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]",
                                                               arguments: ["s": selector], in: try #require(window.frame), contentWorld: .defaultClient) as? [Double]
            let point = try #require(box)
            return CGPoint(x: point[0], y: point[1])
        }

        let tiny = try #require(await Pointing.part(at: try await center(".tiny"), in: window.web, frame: frame))
        #expect(tiny.path == ":root > body:nth-of-type(1) > div:nth-of-type(1)" && tiny.tag == "div" && tiny.kind == "this block")
        #expect(tiny.rect.size == CGSize(width: window.web.frame.width, height: 100))
        let cell = try #require(await Pointing.part(at: try await center("td"), in: window.web, frame: frame))
        #expect(cell.path == ":root > body:nth-of-type(1) > table:nth-of-type(1) > tbody:nth-of-type(1) > tr:nth-of-type(1) > td:nth-of-type(1)")
        #expect(cell.kind == "this cell")
        let card = try #require(await Pointing.part(at: try await center(".inner"), in: window.web, frame: frame))
        #expect(card.path == ":root > body:nth-of-type(1) > section:nth-of-type(1)" && card.kind == "this section")
        for part in [tiny, cell, card] { #expect(!part.path.contains(".") && !part.path.contains("#") && !part.path.contains("my-card")) }
        #expect(await Pointing.rects([cell.path, ":root > body:nth-of-type(1) > aside:nth-of-type(1)"], in: window.web, frame: frame) == [cell.rect, nil])
        #expect(try await run(window, "return [window.spied === undefined, typeof part, typeof paths, typeof tags]") as? [AnyHashable]
                == [true, "undefined", "undefined", "undefined"])

        // Point mode over the page: every click is the overlay's, and picks the part under it.
        let overlay = PointOverlay(window, motion: .reduced)
        window.point(overlay)
        let at = NSPoint(x: cell.rect.midX, y: window.area.bounds.height - cell.rect.midY)
        #expect(window.area.hitTest(at) === overlay && window.area.hitTest(NSPoint(x: 5, y: 5)) === overlay)
        // As the window routes a press: to the view its content's hitTest finds.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: offscreen.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let target = try #require(offscreen.window.contentView?.hitTest(at))
            type == .leftMouseDown ? target.mouseDown(with: event) : target.mouseUp(with: event)
        }
        #expect(await wait(10, until: { overlay.picks.first?.path == cell.path }))
        #expect(overlay.banner == ["Say what should change", "Hold ⌥ and click to add a part", "Esc", "Back"])
        await wait(0.3)
        #expect(try await run(window, "return window.clicks ?? 0") as? Int == 0)
        // ⌥ adds a part once a frame is drawn, even while a follow asks about the parts there were: the click's
        // question goes first, the follow's second, and the page answers them in that order.
        let inner = try await center(".inner")
        let adding = Task { @MainActor in await overlay.click(at: inner, adding: true) }
        let following = Task { @MainActor in await overlay.follow() }
        await adding.value
        await following.value
        #expect(overlay.picks.map(\.path) == [cell.path, card.path] && overlay.picks.map(\.rect) == [cell.rect, card.rect])

        // A reload keeps the mode and its picks, and the frames ask the new page where their parts are: moved by the
        // page before, back where the file has them after.
        _ = try await run(window, "document.querySelector('table').style.marginTop = '200px'; return 0")
        await overlay.follow()
        #expect(overlay.picks.first?.rect.minY == cell.rect.minY + 180)
        window.load()
        try await ready(window)
        #expect(await wait(10, until: { overlay.picks.first?.rect == cell.rect }), "\(String(describing: overlay.picks.first))")
        #expect(window.pointer === overlay && overlay.picks.map(\.path) == [cell.path, card.path] && window.pointable)

        // The wheel scrolls the page, from something's world, and the frames follow it.
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -300, wheel2: 0, wheel3: 0)
            .flatMap { NSEvent(cgEvent: $0) })
        overlay.scrollWheel(with: wheel)
        #expect(await wait(10, until: { overlay.picks.first?.rect.minY == cell.rect.minY - 300 }), "\(String(describing: overlay.picks.first))")
        #expect(try await run(window, "return scrollY") as? Double == 300)
        // Over a box that scrolls, the wheel scrolls the box, not the page.
        await Pointing.scroll(by: CGSize(width: 0, height: 100), at: try await center(".pane"), in: window.web, frame: try #require(window.frame))
        #expect(try await run(window, "return [document.querySelector('.pane').scrollTop, scrollY]") as? [Double] == [100, 300])

        // Esc lets the picks go, then stops the mode.
        var stopped = false
        overlay.stopped = { stopped = true }
        #expect(overlay.escape() && overlay.picks.isEmpty && !stopped && overlay.banner == ["Point at a part of the space", "Esc", "to stop"])
        #expect(overlay.escape() && stopped)
        window.point(nil)
        #expect(overlay.superview == nil && window.pointer == nil)
    }

    /// A picked part gets the composer: ⌥-click adds a part only once one is picked, Return makes a Quick Change and
    /// ⌘↵ adds a comment with the words and the parts, Shift-Return breaks the line; Esc lets the parts go (the
    /// composer with them), a second Esc stops the mode.
    @Test func aPickedPartGetsTheComposer() async throws {
        let home = Home(prefix: "something-window-")
        defer { home.remove() }
        let body = """
            <style>body { margin: 0 } td { width: 120px; height: 40px }</style>
            <table style="margin: 20px"><tr><td>a</td><td>b</td></tr></table>
            <section style="height: 80px; margin-left: 600px"><p>inside</p></section>
            <script>window.done = true</script>
            """
        let space = try home.space("parts", page(nil, body))
        let window = try await home.window(space)
        defer { window.close() }
        let offscreen = Offscreen(window.area)
        window.open()
        try await ready(window)
        let overlay = PointOverlay(window, motion: .reduced)
        var stopped = false, quick: [(String, [String])] = [], comments: [(String, [String])] = []
        overlay.stopped = { stopped = true }
        overlay.quickChange = { quick.append(($0, $1.map(\.kind))) }
        overlay.addComment = { comments.append(($0, $1.map(\.kind))) }
        overlay.eyes = { .listen }
        window.point(overlay)
        let cell = CGPoint(x: 80, y: 40), section = CGPoint(x: 700, y: 120)

        // ⌥ alone does nothing: there is no frame to add to.
        await overlay.click(at: cell, adding: true)
        #expect(overlay.picks.isEmpty && overlay.composer == nil)
        await overlay.click(at: cell, adding: false)
        let composer = try #require(overlay.composer)
        #expect(composer.names == "this cell" && composer.title == window.title && composer.to == "To parts’ assistant")
        #expect(composer.frame == PointComposer.place(PointComposer.size, by: try #require(overlay.picks.last).rect, in: overlay.bounds.size))
        #expect(offscreen.window.firstResponder === composer.field && overlay.banner[1] == "Hold ⌥ and click to add a part")
        #expect(!composer.quickButton.isEnabled && !composer.commentButton.isEnabled)
        await overlay.click(at: section, adding: true)
        #expect(overlay.composer === composer && composer.names == "this cell and this section")
        #expect(composer.frame.minX == PointComposer.place(PointComposer.size, by: try #require(overlay.picks.last).rect, in: overlay.bounds.size).minX)
        // Over the composer, clicks are its own.
        let inside = NSPoint(x: composer.frame.midX, y: overlay.bounds.height - composer.frame.midY)
        #expect(window.area.hitTest(inside).map { $0.isDescendant(of: composer) } == true)

        // Return: a Quick Change; nothing while the words are only spaces; Shift-Return is the field's.
        composer.field.insertText("  ", replacementRange: composer.field.selectedRange())
        #expect(composer.textView(composer.field, doCommandBy: #selector(NSResponder.insertNewline(_:))) && quick.isEmpty)
        composer.field.insertText("Make it smaller", replacementRange: composer.field.selectedRange())
        #expect(composer.quickButton.isEnabled && composer.commentButton.isEnabled)
        #expect(composer.textView(composer.field, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(quick.map(\.0) == ["Make it smaller"] && quick.first?.1 == ["this cell", "this section"])

        // ⌘↵: a comment; the parts go, the mode stays.
        let command = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                    windowNumber: offscreen.window.windowNumber, context: nil, characters: "\r",
                                                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(composer.field.performKeyEquivalent(with: command))
        #expect(comments.map(\.0) == ["Make it smaller"] && comments.first?.1 == ["this cell", "this section"])
        #expect(overlay.picks.isEmpty && overlay.composer == nil && composer.superview == nil && !stopped)

        // Esc: the parts and the composer go, then the mode.
        await overlay.click(at: cell, adding: false)
        #expect(overlay.composer != nil)
        #expect(overlay.escape() && overlay.composer == nil && !stopped && offscreen.window.firstResponder === overlay)
        #expect(overlay.escape() && stopped)
        window.point(nil)
    }

    /// The composer goes under the last part, or over it when there is no room below, on the part's side, 12 points
    /// off every edge.
    @Test func theComposerIsPlacedByItsPart() {
        let size = PointComposer.size, bounds = CGSize(width: 1000, height: 700)
        // Left half: its left edge with the frame's (7 points off the part), 12 under it.
        #expect(PointComposer.place(size, by: CGRect(x: 100, y: 100, width: 200, height: 50), in: bounds)
                == CGRect(x: 93, y: 169, width: 368, height: 118))
        // Right half: its right edge with the frame's.
        #expect(PointComposer.place(size, by: CGRect(x: 700, y: 100, width: 200, height: 50), in: bounds)
                == CGRect(x: 907 - 368, y: 169, width: 368, height: 118))
        // No room below: over the part.
        #expect(PointComposer.place(size, by: CGRect(x: 100, y: 560, width: 200, height: 50), in: bounds)
                == CGRect(x: 93, y: 560 - 7 - 12 - 118, width: 368, height: 118))
        // Never past an edge.
        #expect(PointComposer.place(size, by: CGRect(x: 0, y: 0, width: 990, height: 690), in: bounds)
                == CGRect(x: 12, y: 12, width: 368, height: 118))
        #expect(PointComposer.sentence(["a"]) == "a" && PointComposer.sentence(["a", "b"]) == "a and b"
                && PointComposer.sentence(["a", "b", "c"]) == "a, b and c" && PointComposer.sentence([]).isEmpty)
    }
}
