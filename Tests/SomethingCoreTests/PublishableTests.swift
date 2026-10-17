// Publishable: nothing personal in what the repository publishes. No key, no home folder with a real name, no
// e-mail address, no secret file. Two scans, through git: the files tracked or about to be, and the commits no
// remote holds yet, with their authors (a commit stays in the history even when a later one removes what it added).
// What no scan can see, session content copied into a fixture, stays a rule (AGENTS.md, "Publishable").
import Foundation
import Testing

enum Publishable {
    /// The home folders an example may name.
    static let placeholders: Set<String> = ["example", "me", "you", "name", "user"]
    /// Addresses that name nobody: examples, hosts' no-reply addresses, the user of a clone over SSH.
    static let nobody = ["example.com", "example.org", "noreply.github.com", "noreply@github.com",
                         "noreply@anthropic.com", "git@github.com"]
    static let secretFile = #"(^|/)(\.env(\..*)?|.*\.(pem|key|p12|pfx)|id_(rsa|dsa|ecdsa|ed25519))$"#
    static let home = #"(?:/Users/|/home/|[A-Za-z]:\\Users\\)([A-Za-z0-9._-]+)"#
    // The same folder as a harness writes it in a session folder's name: "-Users-example-Projects-shop".
    static let dashedHome = #"(?:(?<=[/\\"'`])(?:[A-Za-z]-)?--?Users|(?<=[/\\])--?home)-([A-Za-z0-9_]+)"#
    static let mail = #"[A-Za-z0-9][A-Za-z0-9._%+-]*@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"#
    static let keys: [(String, String)] = [
        ("a private key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        ("a model provider's key", #"\bsk-[A-Za-z0-9_-]{20,}"#),
        ("a GitHub token", #"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"#),
        ("an AWS key", #"\bAKIA[0-9A-Z]{16}\b"#),
        ("a Google key", #"\bAIza[0-9A-Za-z_-]{35}"#),
        ("a Slack token", #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#),
    ]

    static func matches(_ pattern: String, _ text: String, group: Int = 0) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range(at: group), in: text).map { String(text[$0]) } }
    }

    /// The kinds of personal data found in `text`, sorted; never the text itself, so a report cannot repeat a secret.
    static func findings(_ text: String) -> [String] {
        var found = Set(keys.filter { !matches($0.1, text).isEmpty }.map(\.0))
        if (matches(home, text, group: 1) + matches(dashedHome, text, group: 1)).contains(where: { !placeholders.contains($0.lowercased()) }) {
            found.insert("a home folder with a real name")
        }
        if matches(mail, text).contains(where: { address in !nobody.contains { address.lowercased().hasSuffix($0) } }) {
            found.insert("an e-mail address")
        }
        return found.sorted()
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The output of a git command in the repository, or nil: no git, not a clone, or a refusal.
    static func git(_ arguments: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

@Suite struct PublishableTests {
    @Test func eachKindIsFound() {
        // Made-up values, cut in two so that this file does not hold one whole.
        let cases: [(String, String)] = [
            ("a private key", "-----BEGIN OPENSSH " + "PRIVATE KEY-----"),
            ("a model provider's key", "key = sk-" + String(repeating: "a1B2", count: 8)),
            ("a GitHub token", "ghp_" + String(repeating: "a1B2", count: 9)),
            ("an AWS key", "AKIA" + String(repeating: "ABCD1234", count: 2)),
            ("a Slack token", "xoxb-" + "1234-abcd-5678"),
            ("a home folder with a real name", "/Users/" + "ada/Projects/shop"),
            ("a home folder with a real name", "/home/" + "ada/.config"),
            ("a home folder with a real name", "~/.claude/projects/-Users-" + "ada-Projects-shop/5b2e.jsonl"),
            ("an e-mail address", "ada@" + "lovelace.dev"),
        ]
        for (kind, text) in cases { #expect(Publishable.findings(text) == [kind], "\(kind)") }
    }

    @Test func whatAnExampleMaySayIsNotFound() {
        for text in ["/Users/example/Projects/bookshop", "/home/me/.config", "ada@example.com",
                     "Co-Authored-By: Claude <noreply@anthropic.com>", "12345+ada@users.noreply.github.com",
                     "~/.claude/projects/-Users-example-Projects-bookshop/5b2e.jsonl", "a stay-at-home-parent",
                     "@media (max-width: 40em)"] {
            #expect(Publishable.findings(text).isEmpty, "\(text)")
        }
    }

    @Test func theFilesHoldNothingPersonal() throws {
        guard let listed = Publishable.git("ls-files", "-z", "--cached", "--others", "--exclude-standard") else { return }
        var problems: [String] = []
        for name in listed.split(separator: "\0").map(String.init) {
            if !Publishable.matches(Publishable.secretFile, name).isEmpty { problems.append("\(name): a secret file") }
            problems += Publishable.findings(name).map { "\(name): \($0), in its name" }
            guard let data = try? Data(contentsOf: Publishable.root.appendingPathComponent(name)) else { continue }
            var kinds = Publishable.findings(String(decoding: data, as: UTF8.self))
            if data.contains(0) { kinds.removeAll { $0 == "an e-mail address" } }   // binary bytes look like addresses by chance
            problems += kinds.map { "\(name): \($0)" }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func theCommitsToPushHoldNothingPersonal() throws {
        guard Publishable.git("rev-parse", "--verify", "--quiet", "HEAD") != nil,
              let remotes = Publishable.git("for-each-ref", "--count=1", "refs/remotes"), !remotes.isEmpty else { return }
        let log = try #require(Publishable.git("log", "--no-color", "--no-show-signature",
                                               "--format=%x00%h%n%ae%n%ce%n%B", "-p", "HEAD", "--not", "--remotes"))
        var problems: [String] = []
        for block in log.split(separator: "\0").map(String.init) {
            let lines = block.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 3 else { continue }
            if !lines[1...2].allSatisfy({ address in Publishable.nobody.contains { address.lowercased().hasSuffix($0) } }) {
                problems.append("commit \(lines[0]): the address of its author or committer")
            }
            problems += Publishable.findings(lines.count > 3 ? lines[3] : "").map { "commit \(lines[0]): \($0)" }
        }
        #expect(problems.isEmpty, "In a commit no remote holds yet: \(problems). Rewrite it before pushing.")
    }
}
