// The template and the four examples of share/ (P15) pass `something check` with no problem at all, as the person's
// spaces, copied as Home's "Make a copy" copies them: once with every right they declare, then with each of those
// rights refused, which they must adapt to. Each stays short enough for an agent to read in one go. The checks run
// in the something program, off the main actor: waiting for them there would hold the queue other suites answer on.
import Foundation
import SomethingCore
import Testing
@testable import something

@Suite(.serialized, .enabled(if: windowServer, windowServerMissing), .leavesNothing("something-examples-")) struct ExamplesTests {
    static let examples = ["agents", "chat", "today", "game"]

    @Test func theExamplesAreTheFourOfTheSpecification() {
        let names = Spaces(root: Home.share.appendingPathComponent("examples")).list().map(\.name)
        #expect(names.sorted() == ExamplesTests.examples.sorted())
    }

    @Test(arguments: ["template"] + examples)
    func passesTheCheck(_ name: String) throws {
        let home = Home(prefix: "something-examples-")
        defer { home.remove() }
        let source = Home.share.appendingPathComponent(name == "template" ? "template.html" : "examples/\(name).html")
        let html = try String(contentsOf: source, encoding: .utf8)
        let lines = html.filter { $0 == "\n" }.count
        #expect(lines <= 300, "\(name) has \(lines) lines; an example stays under about 300")
        try home.space(name, html)
        let checked = try Checked([name, "--json"], home)
        #expect(checked.status == 0 && checked.codes.isEmpty, "\(checked.out)")
        #expect((checked.json["console"] as? [Any])?.isEmpty == true, "\(checked.out)")
        let declared = (checked.json["declaration"] as? [String: Any])?["rights"] as? [String] ?? []
        #expect(!declared.isEmpty)
        for right in declared {
            let refused = try Checked([name, "--json", "--refuse", right], home)
            #expect(refused.status == 0 && refused.codes.isEmpty, "with \(right) refused: \(refused.out)")
        }
    }
}
