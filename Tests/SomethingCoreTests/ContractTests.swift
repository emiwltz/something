// The contract as data and as Swift agree: the state example round-trips through Contract.swift, passes shape.json,
// nil is null, the caps hold, and nothing frozen-v1.json promises is missing from shape.json, codes.json or the guide.
import Foundation
import Testing
@testable import SomethingCore

enum ContractFiles {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let folder = root.appendingPathComponent("share/contract")

    static func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }
    static func object(_ name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data(name)) as? [String: Any], "\(name) is not a JSON object")
    }
    static var guide: String { (try? String(contentsOf: root.appendingPathComponent("share/guide.md"), encoding: .utf8)) ?? "" }
    /// The fixture files of one folder of share/contract, by name.
    static func fixtures(_ folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: self.folder.appendingPathComponent(folder).path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { "\(folder)/\($0)" }
    }
}

/// Checks JSON values against shape.json. Its grammar is in shape.json's own comment.
struct Shape {
    let types: [String: [String: [String]]]

    init(_ shape: [String: Any]) {
        types = shape["types"] as? [String: [String: [String]]] ?? [:]
    }

    /// Every way `value` breaks the type `name`, one line each, with the path; empty when it fits.
    func problems(_ value: Any, type name: String, at path: String = "") -> [String] {
        problems(value, allowed: [name], at: path.isEmpty ? name : path)
    }

    func problems(_ value: Any, allowed: [String], at path: String) -> [String] {
        // The alternative that fits best explains the failure; any perfect fit wins.
        let tries = allowed.map { problems(value, token: $0, at: path) }
        return tries.min { $0.count < $1.count } ?? ["\(path): nothing is allowed"]
    }

    func problems(_ value: Any, token: String, at path: String) -> [String] {
        let wrong = ["\(path): \(value) is not \(token)"]
        switch token {
        case "null": return value is NSNull ? [] : wrong
        case "boolean": return Shape.isBool(value) ? [] : wrong
        case "integer":
            // 1.0 is written as a float: a space would see a number that is not an integer.
            guard let number = value as? NSNumber, !Shape.isBool(value), !CFNumberIsFloatType(number) else { return wrong }
            return []
        case "string": return value is String ? [] : wrong
        case "object": return value is [String: Any] ? [] : wrong
        default: break
        }
        if token.hasPrefix("=") { return value as? String == String(token.dropFirst()) ? [] : wrong }
        if token.hasPrefix("[") {
            guard let array = value as? [Any] else { return wrong }
            let inner = String(token.dropFirst().dropLast())
            return array.enumerated().flatMap { problems($1, allowed: [inner], at: "\(path)[\($0)]") }
        }
        if token.hasPrefix("{") {
            guard let object = value as? [String: Any] else { return wrong }
            let inner = String(token.dropFirst().dropLast())
            return object.keys.sorted().flatMap { problems(object[$0]!, allowed: [inner], at: "\(path).\($0)") }
        }
        guard let keys = types[token] else { return ["\(path): shape.json has no type \(token)"] }
        guard let object = value as? [String: Any] else { return wrong }
        var found: [String] = []
        for (written, allowed) in keys.sorted(by: { $0.key < $1.key }) {
            let key = written.hasPrefix("?") ? String(written.dropFirst()) : written
            if let child = object[key] {
                found += problems(child, allowed: allowed, at: "\(path).\(key)")
            } else if !written.hasPrefix("?") {
                found.append("\(path).\(key) is missing")
            }
        }
        let known = Set(keys.keys.map { $0.hasPrefix("?") ? String($0.dropFirst()) : $0 })
        found += object.keys.filter { !known.contains($0) }.sorted().map { "\(path).\($0) is not in shape.json" }
        return found
    }

    static func isBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

/// What frozen-v1.json promises, and where each promise must still be found.
enum Frozen {
    /// Every frozen key, word, function, event, right or code that is missing, one line each; empty when none is.
    static func missing(frozen: [String: Any], shape: [String: Any], codes: [String: Any], guide: String) -> [String] {
        let types = Shape(shape).types
        var missing: [String] = []
        for (type, keys) in (frozen["keys"] as? [String: [String]] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let described = Set((types[type] ?? [:]).keys.map { $0.hasPrefix("?") ? String($0.dropFirst()) : $0 })
            missing += keys.filter { !described.contains($0) }.map { "key \(type).\($0) is not in shape.json" }
        }
        for (place, words) in (frozen["words"] as? [String: [String]] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let parts = place.split(separator: ".").map(String.init)
            let allowed = types[parts[0]]?[parts[1]] ?? types[parts[0]]?["?" + parts[1]] ?? []
            missing += words.filter { !allowed.contains("=\($0)") }.map { "word \($0) of \(place) is not in shape.json" }
        }
        for function in frozen["functions"] as? [String] ?? [] where !guide.contains("`something.\(function)") {
            missing.append("function something.\(function) is not in the guide")
        }
        // Events are looked for in the row of `something.on` only: a quoted word elsewhere proves nothing.
        let onRow = guide.split(separator: "\n").first { $0.hasPrefix("| `something.on(") } ?? ""
        for event in frozen["events"] as? [String] ?? [] where !onRow.contains("\"\(event)\"") {
            missing.append("event \"\(event)\" is not in the guide")
        }
        for right in frozen["rights"] as? [String] ?? [] where !guide.contains("| `\(right)` |") {
            missing.append("right \(right) is not in the guide's table of rights")
        }
        let kindsLine = guide.split(separator: "\n").first { $0.hasPrefix("Kinds for a right:") } ?? ""
        for kind in frozen["rightKinds"] as? [String] ?? [] where !kindsLine.contains("`\(kind)`") {
            missing.append("right kind \(kind) is not in the guide")
        }
        let described = codes["codes"] as? [String: [String: Any]] ?? [:]
        for code in frozen["codes"] as? [String] ?? [] {
            if described[code] == nil { missing.append("code \(code) is not in codes.json") }
            if described[code]?["from"] as? String == "bridge", !guide.contains("| `\(code)` |") {
                missing.append("bridge code \(code) is not in the guide")
            }
        }
        return missing
    }
}

@Suite struct ContractTests {
    let shape: Shape

    init() throws {
        shape = Shape(try ContractFiles.object("shape.json"))
    }

    /// The engine has drivers: a space writer who reads the guide or the README must not code for launches that fail.
    @Test func theDocsSayTheEngineLaunchesAgents() throws {
        let readme = try String(contentsOf: ContractFiles.root.appendingPathComponent("README.md"), encoding: .utf8)
        for (name, text) in [("guide", ContractFiles.guide), ("README", readme)] {
            #expect(!text.contains("until the drivers arrive") && !text.contains("knows no agent"), "\(name)")
        }
    }

    @Test func theStateExampleRoundTripsByteForByte() throws {
        let example = try ContractFiles.data("state-example.json")
        let state = try JSONDecoder().decode(State.self, from: example)
        // The same JSON written with sorted keys by Foundation's own writer: the bytes the Swift types must give back.
        let reference = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: example),
                                                   options: [.sortedKeys, .withoutEscapingSlashes])
        let encoded = try state.json()
        #expect(encoded == reference, "\(String(decoding: encoded, as: UTF8.self))")
    }

    @Test func theStateExamplePassesTheShape() throws {
        let example = try JSONSerialization.jsonObject(with: ContractFiles.data("state-example.json"))
        #expect(shape.problems(example, type: "State").isEmpty, "\(shape.problems(example, type: "State"))")
    }

    @Test func theShapeCatchesAMissingKeyAWrongWordAndAnExtraKey() throws {
        var example = try ContractFiles.object("state-example.json")
        var agents = try #require(example["agents"] as? [[String: Any]])
        agents[0]["pid"] = nil
        agents[0]["state"] = "sleeping"
        agents[0]["status"] = "working"
        example["agents"] = agents
        #expect(shape.problems(example, type: "State") == [
            "State.agents[0].pid is missing",
            "State.agents[0].state: sleeping is not =idle",
            "State.agents[0].status is not in shape.json",
        ])
    }

    /// A state built from nothing: every unknown fact must still reach the space as null.
    @Test func everyNilKeyIsEncodedAsNull() throws {
        let kind = Kind(launch: false, installed: nil, tested: "1.0.0", seen: nil, reader: "none", note: nil)
        var agent = Agent(id: "a1", kind: "claude", origin: "launched")
        agent.queue = [Queued(id: "q1", text: "Invented.", at: "2026-10-17T09:00:00Z")]
        let item = Item(id: "i1", kind: "tool", author: "agent", text: "ls", at: "2026-10-17T09:00:00Z",
                        tool: Tool(name: "Bash", status: nil))
        let turn = Turn(id: "t1", state: "unknown", started: nil, ended: nil, items: [item])
        let thread = AgentThread(id: "th1", agent: "a1", title: nil, started: nil, turns: [turn])
        let request = Request(id: "r1", agent: "a1", kind: "question", tool: nil, about: nil, at: "2026-10-17T09:00:00Z")
        let kinds = Dictionary(uniqueKeysWithValues: ["claude", "codex", "opencode", "pi", "omp"].map { ($0, kind) })
        let state = State(at: "2026-10-17T09:00:00Z", kinds: kinds, agents: [agent], threads: [thread], requests: [request])

        let json = try #require(try JSONSerialization.jsonObject(with: state.json()) as? [String: Any])
        #expect(shape.problems(json, type: "State").isEmpty, "\(shape.problems(json, type: "State"))")
        let encodedAgent = try #require((json["agents"] as? [[String: Any]])?.first)
        for key in ["name", "folder", "pid", "alive", "evidence", "waiting", "thread", "model", "mode", "effort", "error", "started", "updated"] {
            #expect(encodedAgent[key] is NSNull, "agent.\(key) is \(String(describing: encodedAgent[key]))")
        }
        let options = try #require(encodedAgent["options"] as? [String: Any])
        #expect(["model", "mode", "effort"].allSatisfy { options[$0] is NSNull })
        #expect(encodedAgent["state"] as? String == "unknown")

        let granted = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Granted())) as? [String: Any])
        #expect(shape.problems(granted, type: "Granted").isEmpty, "\(shape.problems(granted, type: "Granted"))")
        #expect(granted["folder"] is NSNull)
    }

    @Test func theCapsHold() {
        let long = String(repeating: "é", count: Limits.characters + 1)
        let cut = Item(id: "i", kind: "message", author: "agent", text: long, at: "2026-10-17T09:00:00Z")
        #expect(cut.truncated && cut.text.count == Limits.characters)
        let whole = Item(id: "i", kind: "message", author: "agent", text: String(long.dropLast()), at: "2026-10-17T09:00:00Z")
        #expect(!whole.truncated && whole.text.count == Limits.characters)

        let items = (1...55).map { Item(id: "i\($0)", kind: "message", author: "agent", text: "Invented.", at: "2026-10-17T09:00:00Z") }
        let turn = Turn(id: "t", state: "done", started: nil, ended: nil, items: items)
        #expect(turn.items.count == Limits.items && turn.items.first?.id == "i6")

        let turns = (1...12).map { Turn(id: "t\($0)", state: "done", started: nil, ended: nil, items: []) }
        let thread = AgentThread(id: "th", agent: "a1", title: nil, started: nil, turns: turns)
        #expect(thread.turns.count == Limits.turns && thread.turns.first?.id == "t3" && !thread.complete)
        #expect(AgentThread(id: "th", agent: "a1", title: nil, started: nil, turns: Array(turns.prefix(10))).complete)
    }

    /// The journal line of contract 7, as written there, fits JournalLine.
    @Test func theJournalLineHasItsShape() throws {
        let line = #"{"at":"2026-10-17T09:00:02Z","action":"send","agent":"a1","kind":"claude","when":"next","text":"Then run the tests.","result":"ok"}"#
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        #expect(shape.problems(object, type: "JournalLine").isEmpty, "\(shape.problems(object, type: "JournalLine"))")
        #expect(shape.problems(["at": "2026-10-17T09:00:02Z", "action": "open", "result": "ok"], type: "JournalLine").isEmpty)
    }

    @Test func anIntegerIsNotWrittenAsAFloat() throws {
        let numbers = try #require(try JSONSerialization.jsonObject(with: Data(#"[1, 1.0]"#.utf8)) as? [Any])
        #expect(shape.problems(numbers[0], token: "integer", at: "n").isEmpty)
        #expect(!shape.problems(numbers[1], token: "integer", at: "n").isEmpty)
    }

    @Test func scopeReadsBothShapes() throws {
        #expect(try JSONDecoder().decode(Scope.self, from: Data(#"{"see":"all"}"#.utf8)) == .all)
        #expect(try JSONDecoder().decode(Scope.self, from: Data(#"{"folders":["~/code/shop"]}"#.utf8)) == .folders(["~/code/shop"]))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Scope.self, from: Data(#"{"see":"some"}"#.utf8)) }
    }

    @Test func nothingFrozenIsMissing() throws {
        let missing = Frozen.missing(frozen: try ContractFiles.object("frozen-v1.json"), shape: try ContractFiles.object("shape.json"),
                                     codes: try ContractFiles.object("codes.json"), guide: ContractFiles.guide)
        #expect(missing.isEmpty, "\(missing)")
    }

    /// A removal anywhere fails: a key from shape.json, a word, a code from codes.json, and from the guide a function,
    /// an event, a right, a right's kind or a bridge code.
    @Test func aRemovalFails() throws {
        let frozen = try ContractFiles.object("frozen-v1.json")
        let codes = try ContractFiles.object("codes.json")
        var shape = try ContractFiles.object("shape.json")
        var types = try #require(shape["types"] as? [String: [String: [String]]])
        types["Agent"]?["pid"] = nil
        types["Agent"]?["state"]?.removeAll { $0 == "=interrupted" }
        shape["types"] = types
        var fewerCodes = codes
        var table = try #require(codes["codes"] as? [String: Any])
        table["TOO_HEAVY"] = nil
        fewerCodes["codes"] = table
        let guide = ContractFiles.guide.replacingOccurrences(of: "`something.resume", with: "`something.continue")
            .replacingOccurrences(of: "| `store` |", with: "| `memory` |")
            .replacingOccurrences(of: "`\"granted\"`: `fn(granted)`", with: "`\"rights\"`: `fn(granted)`")
            .replacingOccurrences(of: "| `BUSY` |", with: "| `OCCUPIED` |")
            .replacingOccurrences(of: "Kinds for a right: `claude`, `codex`, `opencode`, `pi`.", with: "Kinds for a right: `claude`, `codex`, `opencode`.")
        let missing = Frozen.missing(frozen: frozen, shape: shape, codes: fewerCodes, guide: guide)
        #expect(missing == [
            "key Agent.pid is not in shape.json",
            "word interrupted of Agent.state is not in shape.json",
            "function something.resume is not in the guide",
            "event \"granted\" is not in the guide",
            "right store is not in the guide's table of rights",
            "right kind pi is not in the guide",
            "bridge code BUSY is not in the guide",
            "code TOO_HEAVY is not in codes.json",
        ])
    }

    @Test func frozenTypesMatchTheShapeTypes() throws {
        let frozen = try #require(try ContractFiles.object("frozen-v1.json")["keys"] as? [String: [String]])
        #expect(Set(frozen.keys) == Set(shape.types.keys))
    }

    @Test func everyCodeHasALevelAndAFix() throws {
        let codes = try #require(try ContractFiles.object("codes.json")["codes"] as? [String: [String: Any]])
        let frozen = try #require(try ContractFiles.object("frozen-v1.json")["codes"] as? [String])
        #expect(Set(codes.keys) == Set(frozen), "codes.json and frozen-v1.json list different codes")
        for (code, entry) in codes {
            #expect(["bridge", "check", "import"].contains(entry["from"] as? String ?? ""), "\(code) has no from")
            #expect(["fatal", "error", "warning", "info"].contains(entry["level"] as? String ?? ""), "\(code) has no level")
            #expect((entry["fix"] as? String)?.hasSuffix(".") == true, "\(code) has no fix sentence")
            #expect((entry["when"] as? String)?.isEmpty == false, "\(code) has no when")
        }
        #expect(codes.values.filter { $0["from"] as? String == "bridge" }.count == 21)
        #expect(codes.values.filter { $0["from"] as? String == "check" }.count == 26)
    }

    /// The fixtures for later slices are well formed now, so a typo is not found only when their engine arrives.
    @Test func theFixturesAreWellFormed() throws {
        let codes = try #require(try ContractFiles.object("codes.json")["codes"] as? [String: Any])
        let declarations = ContractFiles.fixtures("declarations"), bridge = ContractFiles.fixtures("bridge"),
            exports = ContractFiles.fixtures("exports")
        #expect(declarations.count >= 3 && bridge.count >= 3 && exports.count >= 3)
        for name in declarations + bridge + exports {
            let fixture = try ContractFiles.object(name)
            #expect(fixture["about"] is String, "\(name) has no about")
            let expect = fixture["expect"] as? [String: Any] ?? fixture["answer"] as? [String: Any] ?? [:]
            let named = (expect["problems"] as? [String] ?? []) + [expect["code"] as? String, (expect["error"] as? [String: Any])?["code"] as? String].compactMap { $0 }
            for code in named { #expect(codes[code] != nil, "\(name) names \(code), which codes.json does not know") }
        }
        let results = ["send": "Delivery", "interrupt": "Interrupted", "set": "Applied"]
        for name in bridge {
            let fixture = try ContractFiles.object(name)
            let granted = try #require(fixture["granted"])
            #expect(shape.problems(granted, type: "Granted").isEmpty, "\(name): \(shape.problems(granted, type: "Granted"))")
            let request = try #require(fixture["request"] as? [String: Any])
            let params = request["params"] as? [String: Any] ?? [:]
            if request["method"] as? String == "send", let when = params["when"] {
                #expect(shape.problems(["when": when], type: "SendOptions").isEmpty, "\(name): when is \(when)")
            }
            guard let result = (fixture["answer"] as? [String: Any])?["result"], let method = request["method"] as? String else { continue }
            let type = try #require(results[method], "\(name): no result type for \(method)")
            #expect(shape.problems(result, type: type).isEmpty, "\(name): \(shape.problems(result, type: type))")
        }
        for name in declarations {
            let declaration = try ContractFiles.object(name)["expect"].flatMap { ($0 as? [String: Any])?["declaration"] as? [String: Any] }
            guard let declaration else { continue }
            #expect(shape.problems(declaration, type: "InForce").isEmpty, "\(name): \(shape.problems(declaration, type: "InForce"))")
        }
        // Every export but the one that is not an export of something has the shape of one.
        for name in exports {
            let fixture = try ContractFiles.object(name)
            guard (fixture["expect"] as? [String: Any])?["code"] as? String != "IMPORT_NOT_A_SPACE" else { continue }
            let export = try #require(fixture["export"])
            #expect(shape.problems(export, type: "Export").isEmpty, "\(name): \(shape.problems(export, type: "Export"))")
        }
    }
}
