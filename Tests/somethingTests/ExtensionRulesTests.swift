// What the code of every agent extension (Sources/Agent*) respects, by a scan of its text, comments and strings left
// out (ToolchainTests.code). It cannot trap: a driver or a reader runs inside the app, and a trap there takes the whole
// app down, so no force unwrap, `as!`, `try!` or `fatalError` (architecture 2.3; the conformance suite feeds them
// damaged input). And it stays portable (architecture 5.3): no extension imports Darwin, the host imports it only in
// its platform files (the process table, the spawner, file stamps and the test guard), and an extension guesses no
// home folder: its agent's folders come from the environment it is given.
import Foundation
import Testing

@Suite struct ExtensionRulesTests {
    static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources")
    /// The host's files that may import Darwin.
    static let platform: Set = ["Processes.swift", "Spawn.swift", "Tail.swift", "TestRunGuard.swift"]

    /// The Swift files of each target folder of Sources/ whose name passes `which`, by target/file, with their text.
    static func files(_ which: (String) -> Bool) throws -> [(name: String, text: String)] {
        try FileManager.default.contentsOfDirectory(atPath: sources.path).filter(which).sorted().flatMap { target in
            try FileManager.default.contentsOfDirectory(atPath: sources.appendingPathComponent(target).path).filter { $0.hasSuffix(".swift") }.sorted()
                .map { ("\(target)/\($0)", try String(contentsOf: sources.appendingPathComponent("\(target)/\($0)"), encoding: .utf8)) }
        }
    }

    /// The lines of `text` that can trap, by number: a `!` that unwraps (after a name, `)` or `]`, and not `!=`), and
    /// `fatalError`. `as!` and `try!` are the same `!`.
    static func traps(_ text: String) -> [Int] {
        ToolchainTests.code(text).components(separatedBy: "\n").enumerated().compactMap { number, line in
            line.range(of: #"[A-Za-z0-9_)\]]!(?!=)|\bfatalError\b"#, options: .regularExpression) == nil ? nil : number + 1
        }
    }

    /// The modules `text` imports.
    static func imports(_ text: String) -> Set<String> {
        Set(ToolchainTests.code(text).components(separatedBy: "\n").compactMap { line in
            let words = line.split(separator: " ")
            return words.first == "import" && words.count > 1 ? String(words[1]) : nil
        })
    }

    @Test func noExtensionCanTrap() throws {
        let files = try ExtensionRulesTests.files { $0.hasPrefix("Agent") }
        #expect(files.count >= 10, "Sources/Agent* was not found at \(ExtensionRulesTests.sources.path)")
        for file in files {
            let lines = ExtensionRulesTests.traps(file.text)
            #expect(lines.isEmpty, "Sources/\(file.name) can trap at line \(lines.map(String.init).joined(separator: ", ")): an extension never unwraps by force")
        }
    }

    @Test func theScanSeesTrapsInCodeOnly() {
        #expect(ExtensionRulesTests.traps("let a = b!\nlet c = d as! Int\nlet e = try! f()\nfatalError(\"no\")\nlet g = h![0]\nlet i = j()!") == [1, 2, 3, 4, 5, 6])
        #expect(ExtensionRulesTests.traps(#"""
            // b! in a comment
            if !done, a != b, !(c ?? false) { }
            let text = "Hello! as! try!", raw = #"x!"#
            let k = l?.m ?? n
            """#).isEmpty)
    }

    @Test func darwinStaysInThePlatformFiles() throws {
        for file in try ExtensionRulesTests.files({ $0.hasPrefix("Agent") || $0 == "SomethingAgents" }) {
            let host = file.name.hasPrefix("SomethingAgents/") && ExtensionRulesTests.platform.contains((file.name as NSString).lastPathComponent)
            #expect(host || ExtensionRulesTests.imports(file.text).isDisjoint(with: ["Darwin", "Glibc"]),
                    "Sources/\(file.name) imports Darwin: a port would have to rewrite it. Use Foundation, or a helper of the host's platform files.")
        }
    }

    @Test func anExtensionGuessesNoHome() throws {
        for file in try ExtensionRulesTests.files({ $0.hasPrefix("Agent") }) {
            let code = ToolchainTests.code(file.text)
            #expect(!code.contains("NSHomeDirectory") && !code.contains("homeDirectoryForCurrentUser"),
                    "Sources/\(file.name) guesses the home folder; take it from the environment the reader or the launch is given.")
        }
    }
}
