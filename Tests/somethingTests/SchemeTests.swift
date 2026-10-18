// The something:// scheme serves a space's own files and nothing else: no climbing out of its folder, by `..` or by
// a link, no hidden file, no file next to a single-file space.
import Foundation
import SomethingCore
import Testing
@testable import something

@Suite(.leavesNothing("something-scheme-")) struct SchemeTests {
    func url(_ text: String) -> URL { URL(string: text)! }

    @Test func aFolderSpaceServesItsFilesOnly() throws {
        let home = Home(prefix: "something-scheme-")
        defer { home.remove() }
        let folder = home.places.spaces.appendingPathComponent("board")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git"), withIntermediateDirectories: true)
        for name in ["index.html", "lib/chart.js", "lib/index.html", ".git/config", ".env"] {
            try "invented".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let secret = home.root.appendingPathComponent("secret.txt")
        try "invented secret".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("out.txt"), withDestinationURL: secret)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("up"), withDestinationURL: home.root)
        let scheme = Scheme(space: try #require(Spaces(root: home.places.spaces).named("board")))
        let real = folder.resolvingSymlinksInPath()

        #expect(scheme.page == url("something://space/"))
        #expect(scheme.file(for: url("something://space/")) == real.appendingPathComponent("index.html"))
        #expect(scheme.file(for: url("something://space/lib/chart.js")) == real.appendingPathComponent("lib/chart.js"))
        #expect(scheme.file(for: url("something://space/lib/")) == real.appendingPathComponent("lib/index.html"))
        for refused in ["something://space/../secret.txt", "something://space/%2e%2e/secret.txt", "something://space/lib/..%2F..%2Fsecret.txt",
                        "something://space/out.txt", "something://space/up/secret.txt", "something://space/.git/config",
                        "something://space/.env", "something://space/missing.js", "something://other/index.html",
                        "https://space/index.html"] {
            #expect(scheme.file(for: url(refused)) == nil, "\(refused)")
        }
    }

    @Test func aSingleFileSpaceServesOnlyItself() throws {
        let home = Home(prefix: "something-scheme-")
        defer { home.remove() }
        let space = try home.space("today", "<p>invented</p>")
        try "invented".write(to: home.places.spaces.appendingPathComponent("other.html"), atomically: true, encoding: .utf8)
        let scheme = Scheme(space: space)
        #expect(scheme.page == url("something://space/today.html"))
        #expect(scheme.file(for: url("something://space/today.html")) == space.location)
        #expect(scheme.file(for: url("something://space/")) == space.location)
        #expect(scheme.file(for: url("something://space/other.html")) == nil)
        #expect(scheme.file(for: url("something://space/../spaces/other.html")) == nil)
    }

    /// The app's page holds the space in a frame that may neither replace the page nor open a window, and is not a
    /// file of the space.
    @Test func theAppsPageHoldsTheSpaceInASandbox() throws {
        let home = Home(prefix: "something-scheme-")
        defer { home.remove() }
        let scheme = Scheme(space: try home.space("today", "<p>invented</p>"))
        let shell = String(decoding: scheme.shellPage, as: UTF8.self)
        #expect(shell.contains(#"<iframe sandbox="allow-scripts allow-same-origin allow-forms""#))
        #expect(shell.contains(#"src="something://space/today.html""#))
        #expect(Scheme.shell == url("something://app/") && scheme.file(for: Scheme.shell) == nil)
        #expect(Scheme.shellPolicy.contains("frame-src something://space") && !Scheme.shellPolicy.contains("*"))
        // A name that HTML would read as an entity is escaped, so the frame asks for the file that is there.
        // A space opened by path may have any name.
        let file = home.root.appendingPathComponent("a&lt.html")
        try "<p>invented</p>".write(to: file, atomically: true, encoding: .utf8)
        let odd = Scheme(space: try #require(Spaces(root: home.places.spaces).locate(file.path)))
        #expect(String(decoding: odd.shellPage, as: UTF8.self).contains(#"src="something://space/a&amp;lt.html""#))
    }
}
