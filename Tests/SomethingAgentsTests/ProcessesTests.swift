// Processes: a snapshot of this Mac through libproc, checked on processes the test owns: itself, and a `sleep` it
// starts in a throwaway folder.
import Darwin
import Foundation
import Testing
@testable import SomethingAgents

@Suite struct ProcessesTests {
    @Test func aSnapshotGivesParentsGroupsStartsAndForKnownNamesArgumentsAndFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("processes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        sleeper.currentDirectoryURL = folder
        try sleeper.run()
        defer { sleeper.terminate(); sleeper.waitUntilExit() }

        let processes = Processes(known: ["sleep"])
        let snapshot = processes.snapshot()
        let me = try #require(snapshot[getpid()])
        #expect(me.parent == getppid() && me.group == getpgrp())
        #expect(me.arguments == nil && me.folder == nil, "a name no reader knows: neither is read")
        #expect(abs(me.started.timeIntervalSinceNow) < 24 * 3600 && me.started < Date())
        let sleep = try #require(snapshot[sleeper.processIdentifier])
        #expect(sleep.name == "sleep" && sleep.parent == getpid())
        #expect(sleep.arguments == ["/bin/sleep", "30"])
        #expect(sleep.folder.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == folder.resolvingSymlinksInPath().path)
        #expect(snapshot.processes.count > 10, "every process of this Mac, not only the test's")
        // The arguments are kept per pid and start time: the second snapshot gives the same ones.
        #expect(processes.snapshot()[sleeper.processIdentifier]?.arguments == ["/bin/sleep", "30"])
    }

    @Test func openFilesAreGivenForTheProcessAskedFor() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("open-\(UUID().uuidString).jsonl").path
        FileManager.default.createFile(atPath: path, contents: Data("{}\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let handle = try #require(FileHandle(forReadingAtPath: path))
        defer { try? handle.close() }
        let files = try #require(Processes(known: []).snapshot().openFiles(getpid()))
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        #expect(files.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved })
        #expect(Processes.openFiles(-1) == nil && Processes.info(-1) == nil)
    }
}
