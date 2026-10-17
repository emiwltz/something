// The space window in a real WKWebView, never shown: nothing reaches the network (criterion 9), no space reads
// another's storage, the bridge answers the page and only the page, links go to the link window, the rights are
// asked once and remembered, and the window reloads when the space changes. Serialized: each test turns the run loop.
import AppKit
import Foundation
import SomethingAgents
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized, .enabled(if: windowServer, windowServerMissing)) struct SpaceWindowTests {
    init() {
        // WebKit's processes talk to an application; this one never shows in the Dock and never takes the focus.
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    /// Every way a page could reach a server, aimed at a listener on 127.0.0.1. The listener must see nothing.
    @Test func nothingReachesTheNetwork() async throws {
        let home = Home(), listener = try Listener()
        defer { home.remove(); listener.stop() }
        let base = "http://127.0.0.1:\(listener.port)"

        // The listener works, and WebKit without something's lock reaches it: zero hits below means something.
        let plain = WKWebViewConfiguration()
        plain.websiteDataStore = .nonPersistent()
        let control = WKWebView(frame: .zero, configuration: plain)
        control.loadHTMLString("<img src=\"\(base)/control\">", baseURL: nil)
        #expect(await wait(until: { listener.hits.count == 1 }), "the control did not reach the listener: \(listener.hits)")

        let ask = FakeAsk()
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
        // Real clicks of the mouse, sent to the view of a window that is never shown: on a link of the page, and on
        // links inside closed shadow roots, where no script of something can see them.
        let offscreen = Offscreen(window.web)
        for x in [50.0, 400] {
            try offscreen.click(x: x, y: 590)
            await wait(0.3)
        }
        await wait(3)
        #expect(try await run(window, "return [window.innerClicked, window.freshClicked]") as? [Bool] == [true, true])
        #expect(listener.hits.count == 1, "reached: \(listener.hits.dropFirst().joined(separator: " | "))")
        // A clicked link goes to the link window instead, which the person cancelled here.
        #expect(ask.links.map(\.path) == ["/link", "/blank", "/dispatched", "/area", "/svg", "/top-link", "/parent-link", "/real-click"])
        #expect(window.web.url == Scheme.shell, "the app's page is still the main frame")
        #expect(try await run(window, "return location.origin + location.pathname") as? String == "something://space/lockdown.html")
    }

    /// The one gap left (README, "Security"): a real click on a link that opens a new window (target="_blank") inside a
    /// closed shadow root, where no script of something sees it, makes WebKit open one connection to the link's server
    /// before the sandbox refuses the window. Marked as known: when WebKit stops doing it, Swift Testing reports that
    /// the known issue was not recorded, and this test and the README's paragraph are updated.
    @Test func theKnownGap() async throws {
        let home = Home(), listener = try Listener()
        defer { home.remove(); listener.stop() }
        let window = try await home.window(try home.space("gap", page(nil, """
            <div id="host" style="position: fixed; inset: 0"></div>
            <script>
              document.getElementById("host").attachShadow({ mode: "closed" }).innerHTML =
                `<a target="_blank" href="http://127.0.0.1:\(listener.port)/gap" style="position: fixed; inset: 0">gap</a>`;
              window.done = true;
            </script>
            """)))
        defer { window.close() }
        window.open()
        try await ready(window)
        try Offscreen(window.web).click(x: 450, y: 320)
        await wait(3)
        withKnownIssue("WebKit connects to the server of a new-window link in a closed shadow root") {
            #expect(listener.hits.isEmpty, "reached: \(listener.hits)")
        }
    }

    /// Every space has the same origin, something://space, so each window has its own data store. Two spaces open at
    /// the same time share nothing: no storage, no cookie, no database, no cache, no message between windows.
    @Test func noSpaceReadsAnothersStorage() async throws {
        let home = Home(), ask = FakeAsk()
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
        #expect(try await run(a, """
            localStorage.setItem("kept", "from a");
            document.cookie = "kept=from-a";
            await new Promise((done, failed) => {
              const opening = indexedDB.open("kept");
              opening.onupgradeneeded = () => opening.result.createObjectStore("store");
              opening.onsuccess = () => {
                const writing = opening.result.transaction("store", "readwrite");
                writing.objectStore("store").put("from a", "key");
                writing.oncomplete = done;
                writing.onerror = failed;
              };
              opening.onerror = failed;
            });
            if (self.caches) await (await caches.open("kept")).put("https://example.com/kept", new Response("from a"));
            new BroadcastChannel("kept").postMessage("from a");
            return [localStorage.getItem("kept"), (await indexedDB.databases()).map((d) => d.name).join()]
            """) as? [String] == ["from a", "kept"])
        await wait(0.5)
        #expect(try await run(a, "return heard") as? [String] == ["from a"], "a message reaches the space's own listener")
        #expect(try await run(b, """
            return [localStorage.getItem("kept"), document.cookie.includes("kept"), (await indexedDB.databases()).length,
                    self.caches ? await caches.has("kept") : false, heard.length]
            """) as? [AnyHashable] == [NSNull(), false, 0, false, 0])

        // Storage ends with the window: the same space, opened again, starts empty.
        a.close()
        let again = try await home.window(try #require(Spaces(root: home.places.spaces).named("space-a")))
        defer { again.close() }
        again.open()
        try await ready(again)
        #expect(try await run(again, "return localStorage.getItem('kept')") == nil)
    }

    @Test func theBridgeAnswersThePageAndOnlyThePage() async throws {
        let home = Home()
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
        for _ in 0..<100 where framed == nil {
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

        // Links: one window at a time, and none after "Block links until reload". Each one is journaled.
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
        ask.link = .block
        #expect(try await run(window, "return await something.open('https://example.com/c')") as? Bool == false)
        #expect(try await run(window, "return await something.open('https://example.com/d')") as? Bool == false)
        #expect(ask.links.count == 2)
        let journal = try Journal(folder: home.places.journals).last(10, space: "bridge")
        // The second call ends first, while the first one waits on the person.
        #expect(journal.map(\.result) == ["RIGHT_NOT_GRANTED", "BUSY", "ok", "ok", "ok"])
    }

    @Test func aModeThatLowersAskingIsConfirmed() async throws {
        let home = Home()
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

    /// The rights window says that pi never asks before it acts, for launch:pi and for launch, which covers pi.
    @Test func theRightsWindowSaysThatPiNeverAsks() {
        #expect(Ask.words(for: "launch:pi").hasSuffix("(pi runs commands and edits files without asking you first)"))
        #expect(Ask.words(for: "launch").contains("pi, one of them, runs commands and edits files without asking you first"))
        #expect(!Ask.words(for: "launch:claude").contains("without asking"))
    }

    /// granted.limits is the table of contract 3.7, as the contract's own fixtures give it.
    @Test func theLimitsAreTheContracts() throws {
        let bridge = Home.share.appendingPathComponent("contract/bridge")
        let cases = try FileManager.default.contentsOfDirectory(at: bridge, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        #expect(!cases.isEmpty)
        for file in cases {
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let limits = (fixture?["granted"] as? [String: Any])?["limits"] as? [String: [String]]
            #expect(limits == Engine.limits, "\(file.lastPathComponent)")
        }
    }

    @Test func rightsAreAskedOnceAndRemembered() async throws {
        let home = Home()
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
                                                 folder: FolderQuestion(declared: "~/code/shop", found: shop.path))])
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
        let home = Home(), ask = FakeAsk()
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

    /// A space opened by path keeps its answers while its window is open, and nowhere else: a file that lands at the
    /// same path later is asked again.
    @Test func aSpaceOpenedByPathIsNotRemembered() async throws {
        let home = Home(), ask = FakeAsk()
        defer { home.remove() }
        let file = home.root.appendingPathComponent("Downloads/board.html")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try page(#"{"contract": 1, "rights": ["state"]}"#, "<p>one</p>").write(to: file, atomically: true, encoding: .utf8)
        let space = try #require(Spaces(root: home.places.spaces).locate(file.path))
        let first = try await home.window(space, ask)
        first.open()
        #expect(ask.questions.count == 1 && first.granted.rights == ["state"])
        first.load()
        #expect(ask.questions.count == 1, "a reload asks nothing new")
        first.close()
        #expect(!FileManager.default.fileExists(atPath: home.places.grants.path))
        let second = try await home.window(space, ask)
        defer { second.close() }
        second.open()
        #expect(ask.questions.count == 2)
    }

    @Test func aGrantsFileThatDoesNotReadIsLeftAndSaid() async throws {
        let home = Home()
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
        let home = Home()
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
        for _ in 0..<100 where try await run(window, "return window.changes") as? Int != 1 { await wait(0.05) }
        #expect(try await run(window, "return window.changes") as? Int == 1)
    }

    @Test func theWindowReloadsWhenTheSpaceChanges() async throws {
        let home = Home()
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
}
