// AssistantBuild's placed program: a copy of this clone's build that carries the fixed LC_UUID and a valid signature,
// so that the folders WebKit names after it are made once per machine.
import Foundation
import Testing

@Suite struct AssistantBuildTests {
    @Test func aStampedCopyCarriesTheFixedUUIDAndStillVerifies() throws {
        try #require(FileManager.default.isExecutableFile(atPath: AssistantBuild.clonesProgram.path), "swift build made no program")
        let folder = FileManager.default.scratch("assistant-build-")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("something")
        try FileManager.default.copyItem(at: AssistantBuild.clonesProgram, to: copy)
        let fixed = withUnsafeBytes(of: AssistantBuild.fixedUUID.uuid) { Data($0) }
        let before = try Data(contentsOf: copy)
        let built = try #require(AssistantBuild.uuidRange(in: before))
        #expect(before[built] != fixed, "a build has its own identity")
        try AssistantBuild.stamp(copy)
        let after = try Data(contentsOf: copy)
        #expect(AssistantBuild.uuidRange(in: after).map { after[$0] } == fixed)
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", copy.path]
        try verify.run()
        verify.waitUntilExit()
        #expect(verify.terminationStatus == 0, "the stamped copy is signed again")
        #expect(AssistantBuild.uuidRange(in: Data("#!/bin/sh\n".utf8)) == nil)
    }
}
