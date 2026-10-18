// A space's declaration: finds the <script type="application/json" id="something"> block or a folder's
// something.json, applies the defaults, and says every problem with its code. Only JSON that does not parse and a
// contract higher than 1 keep a space from displaying; everything else is a warning and the space opens.
import Foundation

/// The declaration in force, once defaults apply: the `InForce` shape of share/contract/shape.json.
public struct Declaration: Equatable, Sendable, EveryKey {
    public var contract: Int
    public var title: String
    public var description: String?
    public var agents: Scope
    /// Known rights this engine can honour, each once, in the declared order.
    public var rights: [String]
    public var folder: String?

    /// The declaration of a space that declares nothing: contract 1, its own name, no right, only its own agents.
    public init(name: String) {
        (contract, title, description, agents, rights, folder) = (1, name, nil, .folders([]), [], nil)
    }

    /// The highest contract this engine knows.
    public static let known = 1
    static let keys: Set = ["contract", "title", "description", "agents", "rights", "folder"]
    static let rightWords: Set = ["state", "send", "launch", "store"]
    /// The kinds a send or launch right may name. omp is known, but this engine cannot honour it.
    static let rightKinds: Set = ["claude", "codex", "opencode", "pi"], unavailableKinds: Set = ["omp"]
}

/// What reading a declaration found.
public struct DeclarationReading: Equatable, Sendable {
    /// What is in force; nil when the space must not be displayed.
    public var declaration: Declaration?
    /// Known rights this engine cannot honour, and words that are not rights: each once, in the declared order.
    public var unavailable: [String] = [], unknown: [String] = []
    public var problems: [Problem] = []
    /// The contract the space declares, as its export carries it: the number of its `contract` key (a fraction
    /// rounded up), 1 when it declares none or a value that is not a number above 1.
    public var contract = 1
}

extension Declaration {
    /// Reads the declaration of `space` from its files. Adds what only the disk can tell: a declared folder missing
    /// on this Mac (`~` is `home`), and a space heavier than 5 MB. Never throws: a file that cannot be read is a
    /// declaration that is missing or unreadable, and the problem's message says it could not be read.
    public static func read(_ space: Space, home: URL) -> DeclarationReading {
        var reading = declared(in: space)
        guard let declaration = reading.declaration else { return reading }
        if let folder = declaration.folder {
            var isFolder: ObjCBool = false
            if let path = expand(folder, home: home) {
                if !FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) || !isFolder.boolValue {
                    reading.problems.append(Problem("FOLDER_MISSING", "The folder \(folder) does not exist on this Mac."))
                }
            } else {
                reading.problems.append(Problem("FOLDER_MISSING", "folder is \(folder): it must be absolute or start with ~, for example ~/code/shop."))
            }
        }
        let size = space.size()
        if size.bytes > Size.heavy {
            reading.problems.append(Problem("TOO_HEAVY", "The space weighs \(Size.words(size.bytes)); the limit is 5 MB."))
        }
        return reading
    }

    /// What the files of `space` declare, before what only the disk can tell.
    static func declared(in space: Space) -> DeclarationReading {
        let page = space.page.lastPathComponent
        var html: String?, pageError: String?
        do { html = String(decoding: try Data(contentsOf: space.page), as: UTF8.self) } catch { pageError = error.localizedDescription }
        let file = space.location.appendingPathComponent("something.json")
        let json = space.form == .folder && FileManager.default.fileExists(atPath: file.path) ? (try? Data(contentsOf: file)) ?? Data() : nil
        var reading = read(html: html, json: json, name: space.name, page: page)
        // A page that is there but cannot be read may well have a block: saying it has none would be false.
        if let pageError, FileManager.default.fileExists(atPath: space.page.path), let i = reading.problems.firstIndex(where: { $0.code == "DECLARATION_MISSING" }) {
            reading.problems[i] = Problem("DECLARATION_MISSING", "\(page) could not be read (\(pageError)); the space opens with no right.", where: Where(file: page))
        }
        return reading
    }

    /// Reads a declaration from the page's HTML and, for a folder space, the bytes of its something.json.
    /// `name` is the default title; `page` names the HTML file in problems.
    static func read(html: String?, json: Data?, name: String, page: String) -> DeclarationReading {
        var reading = DeclarationReading()
        let block = html.flatMap(Self.block(in:))
        let text: Data, file: String
        if let json {
            if block != nil {
                reading.problems.append(Problem("DECLARATION_TWICE", "Both something.json and a block in \(page) declare this space; something.json is used."))
            }
            (text, file) = (json, "something.json")
        } else if let block {
            (text, file) = (Data(block.utf8), page)
        } else {
            reading.declaration = Declaration(name: name)
            reading.problems.append(Problem("DECLARATION_MISSING", "\(page) has no <script type=\"application/json\" id=\"something\"> block.", where: Where(file: page)))
            return reading
        }
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: text) as? [String: Any] else {
                throw SpaceError("it is not a JSON object")
            }
            object = parsed
        } catch {
            let why = (error as? SpaceError)?.message ?? (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "\(error)"
            reading.problems.append(Problem("DECLARATION_UNREADABLE", "The declaration in \(file) is not valid JSON: \(why)", where: Where(file: file)))
            return reading
        }

        var declaration = Declaration(name: name)
        var problems: [Problem] = []
        switch object["contract"] {
        case nil:
            problems.append(Problem("CONTRACT_MISSING", "The declaration has no contract key; it is read as 1."))
        case let number as NSNumber where !isBool(number) && number.doubleValue > Double(known):
            reading.problems.append(Problem("CONTRACT_TOO_NEW", "The space was written for contract \(number); this engine knows contract \(known)."))
            // A contract too large for an Int is still too new everywhere.
            reading.contract = number.doubleValue < Double(Int.max) ? Int(number.doubleValue.rounded(.up)) : Int.max
            return reading
        case let number as NSNumber where !isBool(number) && !isFloat(number) && number.intValue == known:
            break
        case let other?:
            problems.append(Problem("CONTRACT_MISSING", "contract is \(Self.written(other)), not the whole number 1; it is read as 1."))
        }
        // A title, description or folder that is not text is left out without a problem: contract 1 has no code for it.
        if let title = object["title"] as? String { declaration.title = title }
        declaration.description = object["description"] as? String
        declaration.folder = object["folder"] as? String
        if let agents = object["agents"] {
            let data = try? JSONSerialization.data(withJSONObject: agents, options: .fragmentsAllowed)
            let scope = data.flatMap { try? JSONDecoder().decode(Scope.self, from: $0) }
            if let scope, !scope.hasRelativeFolder {
                declaration.agents = scope
            } else {
                problems.append(Problem("SCOPE_INVALID", "agents is neither {\"see\": \"all\"} nor {\"folders\": [...]} of paths that are absolute or start with ~; the space sees only the agents it launches."))
            }
        }
        switch object["rights"] {
        case nil: break
        case let words as [Any]:
            for word in words {
                guard let word = word as? String else { add("\(word)", to: &reading.unknown); continue }
                switch right(word) {
                case .known: add(word, to: &declaration.rights)
                case .unavailable: add(word, to: &reading.unavailable)
                case .unknown: add(word, to: &reading.unknown)
                }
            }
        case let other?:
            problems.append(Problem("UNKNOWN_RIGHT", "rights is \(Self.written(other)), not a list of words; no right is asked."))
        }
        problems += reading.unavailable.map { Problem("RIGHT_UNAVAILABLE", "\"\($0)\" is a right this engine cannot honour.") }
        problems += reading.unknown.map { Problem("UNKNOWN_RIGHT", "\"\($0)\" is not a right of contract 1.") }
        problems += object.keys.filter { !keys.contains($0) }.sorted().map { Problem("UNKNOWN_KEY", "\"\($0)\" is not a declaration key; it is ignored.") }
        reading.declaration = declaration
        reading.problems += problems
        return reading
    }

    enum Right { case known, unavailable, unknown }

    /// What a right's word is: `state`, `store`, `send`, `launch`, or `send:` and `launch:` with a kind.
    static func right(_ word: String) -> Right {
        let parts = word.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard rightWords.contains(parts[0]) else { return .unknown }
        guard parts.count == 2 else { return .known }
        guard parts[0] == "send" || parts[0] == "launch" else { return .unknown }
        return rightKinds.contains(parts[1]) ? .known : unavailableKinds.contains(parts[1]) ? .unavailable : .unknown
    }

    /// The text of the first <script type="application/json" id="something"> in `html`, whatever the order, case and
    /// quoting of its attributes; nil when there is none. A script without that type is code the page runs, not a
    /// declaration, so it does not count; nor does a block inside an HTML comment, which the page does not hold.
    /// When there are several blocks the first wins, without a warning.
    static func block(in html: String) -> String? {
        let comment = try! NSRegularExpression(pattern: #"<!--.*?-->"#, options: .dotMatchesLineSeparators)
        let html = comment.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let script = try! NSRegularExpression(pattern: #"<script\b([^>]*)>(.*?)</script\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let attribute = try! NSRegularExpression(pattern: #"([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#)
        for match in script.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let attributes = String(html[Range(match.range(at: 1), in: html)!])
            var found: [String: String] = [:]
            for pair in attribute.matches(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) {
                let name = String(attributes[Range(pair.range(at: 1), in: attributes)!]).lowercased()
                let value = (2...4).compactMap { Range(pair.range(at: $0), in: attributes) }.first.map { String(attributes[$0]) } ?? ""
                found[name] = found[name] ?? value
            }
            let type = found["type"]?.trimmingCharacters(in: .whitespaces).lowercased()
            if type == "application/json", found["id"] == "something" {
                return String(html[Range(match.range(at: 2), in: html)!])
            }
        }
        return nil
    }

    /// An absolute path for a declared one: `~` is `home`; nil for a relative path, which the contract does not allow.
    public static func expand(_ path: String, home: URL) -> String? {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.path + path.dropFirst() }
        return path.hasPrefix("/") ? path : nil
    }

    /// A value as JSON writes it, so a message shows "1" as text and true as true.
    private static func written(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
    }

    private static func add(_ word: String, to list: inout [String]) {
        if !list.contains(word) { list.append(word) }
    }

    /// JSON's true and false arrive as numbers; objCType tells them apart, on every platform Foundation runs on.
    private static func isBool(_ number: NSNumber) -> Bool { String(cString: number.objCType) == "c" }
    private static func isFloat(_ number: NSNumber) -> Bool { ["d", "f"].contains(String(cString: number.objCType)) }
}

extension Scope {
    /// A folder the contract does not allow: neither absolute nor starting with ~.
    var hasRelativeFolder: Bool {
        guard case .folders(let folders) = self else { return false }
        return folders.contains { Declaration.expand($0, home: URL(fileURLWithPath: "/")) == nil }
    }
}
