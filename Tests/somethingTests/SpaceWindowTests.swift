// The space window in a real WKWebView, never shown: nothing reaches the network (criterion 9), no space reads
// another's storage, the bridge answers the page and only the page, links go to the link window, the rights are
// asked once and remembered, and the window reloads when the space changes. Serialized: each test turns the run loop.
import AppKit
import Foundation
import SomethingCore
import Testing
import WebKit
@testable import something

@MainActor @Suite(.serialized) struct SpaceWindowTests {
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
            <script>
              const base = "\(base)";
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
              ];
              for (const attempt of tries) { try { const p = attempt(); if (p && p.catch) p.catch(() => {}); } catch (e) {} }
              // What a space may load still loads: its own file and an inline image.
              const dot = new Image();
              dot.src = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";
              Promise.all([fetch(location.href).then((r) => r.ok), dot.decode().then(() => dot.naturalWidth === 1)])
                .then((own) => { window.own = own; window.done = true; }, () => { window.own = "failed"; window.done = true; });
            </script></body></html>
            """), ask)
        defer { window.close() }
        window.open()
        try await ready(window.web)
        #expect(try await run(window.web, "return window.done") as? Bool == true, "the page did not run its tries")
        #expect(try await run(window.web, "return window.own") as? [Bool] == [true, true], "the space's own loads failed")
        await wait(3)
        #expect(listener.hits.count == 1, "reached: \(listener.hits.dropFirst().joined(separator: " | "))")
        // A clicked link goes to the link window instead, which the person cancelled here.
        #expect(ask.links.map(\.path) == ["/link", "/blank"])
        #expect(window.web.url?.scheme == "something")
    }

    @Test func noSpaceReadsAnothersStorage() async throws {
        let home = Home(), ask = FakeAsk()
        defer { home.remove() }
        let a = try await home.window(try home.space("space-a", page(nil, "<script>window.done = true</script>")), ask)
        defer { a.close() }
        a.open()
        try await ready(a.web)
        #expect(try await run(a.web, "localStorage.setItem('kept', 'from a'); return localStorage.getItem('kept')") as? String == "from a")
        #expect(ask.questions.isEmpty, "a space that declares no right is asked nothing")

        let b = try await home.window(try home.space("space-b", page(nil, "<script>window.done = true</script>")))
        defer { b.close() }
        b.open()
        try await ready(b.web)
        #expect(try await run(b.web, "return localStorage.getItem('kept')") == nil)

        // Storage ends with the window: the same space, opened again, starts empty.
        a.close()
        let again = try await home.window(try #require(Spaces(root: home.places.spaces).named("space-a")))
        defer { again.close() }
        again.open()
        try await ready(again.web)
        #expect(try await run(again.web, "return localStorage.getItem('kept')") == nil)
    }

    @Test func theBridgeAnswersThePageAndOnlyThePage() async throws {
        let home = Home()
        defer { home.remove() }
        let ask = FakeAsk()
        let window = try await home.window(try home.space("bridge", page(#"{"contract": 1, "rights": ["state", "store"]}"#, """
            <script>window.first = something.granted.rights.join(","); window.done = true</script>
            <iframe srcdoc="<script>webkit.messageHandlers.something.postMessage({contract: 1, id: 1, method: 'state', params: {}})
              .then(() => parent.framed = 'answered', (e) => parent.framed = 'refused')</script>"></iframe>
            """)), ask)
        defer { window.close() }
        window.open()
        try await ready(window.web)
        #expect(try await run(window.web, "return window.first") as? String == "state,store", "granted is set before the page's scripts")
        #expect(try await run(window.web, "return something.contract") as? Int == 1)
        #expect(try await run(window.web, "return (await something.state()).contract") as? Int == 1)
        #expect(try await run(window.web, "await something.store.set('a/b', 2); return await something.store.get('a')") as? [String: Int] == ["b": 2])
        #expect(FileManager.default.fileExists(atPath: home.places.data.appendingPathComponent("bridge.json").path))
        #expect(try await run(window.web, "try { await something.send('a1', 'invented') } catch (e) { return e.code }") as? String == "RIGHT_NOT_GRANTED")
        var framed: String?
        for _ in 0..<100 where framed == nil {
            framed = try await run(window.web, "return window.framed ?? null") as? String
            await wait(0.05)
        }
        #expect(framed == "refused", "a frame inside the space is not answered")

        // Links: one window at a time, and none after "Block links until reload". Each one is journaled.
        #expect(try await run(window.web, "return await something.open('https://example.com/a')") as? Bool == false)
        #expect(ask.links == [URL(string: "https://example.com/a")!])
        window.linkOpen = true
        #expect(try await run(window.web, "try { await something.open('https://example.com/b') } catch (e) { return e.code }") as? String == "BUSY")
        (window.linkOpen, ask.link) = (false, .block)
        #expect(try await run(window.web, "return await something.open('https://example.com/c')") as? Bool == false)
        #expect(try await run(window.web, "return await something.open('https://example.com/d')") as? Bool == false)
        #expect(ask.links.count == 2)
        let journal = try Journal(folder: home.places.journals).last(10, space: "bridge")
        #expect(journal.map(\.result) == ["RIGHT_NOT_GRANTED", "ok", "BUSY", "ok", "ok"])
    }

    @Test func aModeThatLowersAskingIsConfirmed() async throws {
        let home = Home()
        defer { home.remove() }
        let ask = FakeAsk()
        let window = try await home.window(try home.space("modes", page(nil, "")), ask)
        defer { window.close() }
        #expect(window.confirms(mode: "default", kind: "claude"))
        #expect(!window.confirms(mode: "acceptEdits", kind: "claude"))
        ask.lowers = true
        #expect(window.confirms(mode: "never", kind: "codex"))
        #expect(ask.modes == ["acceptEdits", "never"])
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
        try await ready(first.web)
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
        try await ready(window.web)
        #expect(try await run(window.web, "return document.getElementById('word').textContent") as? String == "two")
    }
}
