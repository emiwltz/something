// Lent: how something runs a command it lends, with small invented programs in place of its own: what each way of
// ending gives the agent, and that the commands run one at a time.
import Foundation
import Testing
@testable import SomethingAgents

@Suite struct LentTests {
    /// A report, problems included, is what the program printed; a status of 2 could not run; a program stopped by a
    /// signal, or by the time limit, gave no report, and the reply says which.
    @Test func eachEndIsSaidAsItWas() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func reply(_ script: String) throws -> Lent.Reply {
            let program = folder.appendingPathComponent("program-\(UUID().uuidString)")
            try "#!/bin/sh\n\(script)\n".write(to: program, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
            return Lent.program(program.path, environment: ["PATH": "/usr/bin:/bin"], seconds: 1)(["check", "board"])
        }
        #expect(try reply("echo \"Invented report for $2.\"") == Lent.Reply(ok: true, text: "Invented report for board.\n"))
        #expect(try reply("echo 'Invented: 1 error.'; exit 1") == Lent.Reply(ok: true, text: "Invented: 1 error.\n"))
        #expect(try reply("echo 'Invented: could not run.'; exit 2") == Lent.Reply(ok: false, text: "Invented: could not run.\n"))
        #expect(try reply("exec sleep 30") == Lent.Reply(ok: false, text: "something check board did not finish within 1 seconds."))
        #expect(try reply("kill -9 $$") == Lent.Reply(ok: false, text: "something check board stopped unexpectedly (signal 9)."))
        // Only check's 1 is a report: any other command's 1 is a refusal.
        let refusing = folder.appendingPathComponent("refusing")
        try "#!/bin/sh\necho 'Invented: refused.'\nexit 1\n".write(to: refusing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: refusing.path)
        #expect(Lent.program(refusing.path, environment: [:])(["new", "board"]) == Lent.Reply(ok: false, text: "Invented: refused.\n"))
        #expect(Lent.program(refusing.path, environment: [:])(["check", "board"]) == Lent.Reply(ok: true, text: "Invented: refused.\n"))
    }

    /// Calls made together run one after the other, in order, off the main queue; each reply comes back on it.
    @Test func theCommandsRunOneAtATime() async {
        final class Seen: @unchecked Sendable {
            let lock = NSLock()
            var running = 0, most = 0, order: [String] = []
        }
        let seen = Seen()
        let lent = Lent(run: { words in
            seen.lock.withLock { seen.running += 1; seen.most = max(seen.most, seen.running); seen.order.append(words[1]) }
            Thread.sleep(forTimeInterval: 0.05)
            seen.lock.withLock { seen.running -= 1 }
            return Lent.Reply(ok: !Thread.isMainThread, text: words[1])
        }, refused: { _, _ in })
        let replies = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var replies: [Lent.Reply] = []
                for name in ["one", "two", "three"] {
                    lent.call("something_check", ["name": name]) { reply in
                        precondition(Thread.isMainThread)
                        replies.append(reply)
                        if replies.count == 3 { continuation.resume(returning: replies) }
                    }
                }
            }
        }
        #expect(replies.map(\.text) == ["one", "two", "three"] && replies.allSatisfy(\.ok))
        #expect(seen.most == 1 && seen.order == ["one", "two", "three"])
    }
}
