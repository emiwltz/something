// The preferences: with no window.json, the approved mockup's defaults (its CM_PREFS, copied below); a file that
// does not read is left as it is until the first change; keys a later version wrote survive; every value comes back
// as it was written; and a space gone from the spaces folder leaves its group, the recent ones and its name.
import Foundation
import SomethingCore
import Testing
@testable import something

@Suite(.serialized, .leavesNothing("something-preferences-")) struct PreferencesTests {
    /// The mockup's CM_PREFS, the keys that are preferences (its `used` and `looked` are measures, not choices; its
    /// `sideEyes` left with v6.2's sidebar of names, a window.json that has it keeps it unread). Its
    /// agent, model and effort are the made-up agent it found: here they are nil, the first builder found and its
    /// own model and effort.
    static let mockup: [String: Any] = [
        "open": "last", "apps": true, "resume": true, "sleep": "10 minutes", "awake": "3", "askAll": false, "notify": false,
        "asstOpen": "Reduced", "sticker": true, "motion": "Calm", "appearance": "System", "alt": true,
        "versions": "50", "limit": "500 MB",
    ]

    /// The mockup's value of each preference, read from `values` in the mockup's words.
    static func inMockupWords(_ values: Preferences.Values) -> [String: Any] {
        let capitalized = { (raw: String) in raw.prefix(1).uppercased() + raw.dropFirst() }
        return ["open": values.openAtStart, "apps": values.addToApplications, "resume": values.resume,
                "sleep": values.sleepAfter == 0 ? "Never" : "\(values.sleepAfter) minutes", "awake": "\(values.awakeAtMost)",
                "askAll": values.askEverything, "notify": values.notify, "asstOpen": capitalized(values.assistantAtOpening.rawValue),
                "sticker": values.rememberSticker, "motion": capitalized(values.motion.rawValue),
                "appearance": capitalized(values.appearance.rawValue), "alt": values.holdOption,
                "versions": values.versionsKept == 0 ? "All" : "\(values.versionsKept)", "limit": "\(values.storageLimit) MB"]
    }

    @Test func aMissingFileGivesTheMockupsDefaults() {
        let home = Home(prefix: "something-preferences-")
        defer { home.remove() }
        let preferences = Preferences(home.places)
        let words = PreferencesTests.inMockupWords(preferences.values)
        #expect(Set(words.keys) == Set(PreferencesTests.mockup.keys))
        for (key, value) in PreferencesTests.mockup {
            #expect("\(words[key] ?? "missing")" == "\(value)", "\(key)")
        }
        #expect(preferences.assistant == nil && preferences.model == nil && preferences.effort == nil)
        #expect(preferences.lastOpen == nil && preferences.sticker == nil && !preferences.toured && preferences.hinted.isEmpty)
        #expect(preferences.groups.isEmpty && preferences.folded.isEmpty && preferences.names.isEmpty && preferences.recents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.places.window.path), "reading writes nothing")
    }

    @Test func anUnreadableFileIsLeftUntilTheFirstChange() throws {
        let home = Home(prefix: "something-preferences-")
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        try "{ not json".write(to: home.places.window, atomically: true, encoding: .utf8)
        let preferences = Preferences(home.places)
        #expect(preferences.values == Preferences.Values())
        preferences.notify = false
        #expect(try String(contentsOf: home.places.window, encoding: .utf8) == "{ not json", "the same value changes nothing")
        preferences.notify = true
        #expect(Preferences(home.places).notify)
    }

    /// A value of the wrong type has its default; the others are read, and the keys this version does not know are
    /// written back as they were.
    @Test func unknownKeysSurvive() throws {
        let home = Home(prefix: "something-preferences-")
        defer { home.remove() }
        try FileManager.default.createDirectory(at: home.places.support, withIntermediateDirectories: true)
        let old = #"{"lastOpen": "garden", "toured": true, "awakeAtMost": "many", "later": {"kept": [1, 2]}, "note": "invented"}"#
        try old.write(to: home.places.window, atomically: true, encoding: .utf8)
        let preferences = Preferences(home.places)
        #expect(preferences.lastOpen == "garden" && preferences.toured && preferences.awakeAtMost == 3)
        preferences.motion = .reduced
        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: home.places.window)) as? [String: Any])
        #expect(written["note"] as? String == "invented" && (written["later"] as? [String: Any])?["kept"] as? [Int] == [1, 2])
        #expect(written["motion"] as? String == "reduced" && written["awakeAtMost"] as? Int == 3 && written["lastOpen"] as? String == "garden")
        preferences.lastOpen = nil
        let again = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: home.places.window)) as? [String: Any])
        #expect(again["lastOpen"] == nil && again["note"] as? String == "invented", "a value set to nil leaves the file")
    }

    @Test func everyValueRoundTrips() {
        let home = Home(prefix: "something-preferences-")
        defer { home.remove() }
        var values = Preferences.Values()
        (values.lastOpen, values.assistant, values.model, values.effort) = ("garden", "pi", "invented-model", "high")
        values.listed = ["pi": Options()]
        values.commands = ["claude": [Option(value: "review", label: "Review the page")]]
        (values.askEverything, values.resume, values.toured, values.hinted, values.addToApplications) = (true, false, true, ["ask"], false)
        values.groups = [Preferences.Group(name: "Notes", spaces: ["garden", "pond"]), Preferences.Group(name: "Breaks", spaces: [])]
        (values.folded, values.names, values.recents) = (["Breaks"], ["garden": "My garden"], ["pond", "garden"])
        (values.openAtStart, values.appearance, values.motion, values.assistantAtOpening) = ("new", .dark, .reduced, .open)
        (values.rememberSticker, values.holdOption, values.notify) = (false, false, true)
        values.sticker = Preferences.StickerPlace(trailing: false, bottom: false, offset: 120)
        (values.sleepAfter, values.awakeAtMost, values.versionsKept, values.storageLimit) = (0, 5, 0, 2000)
        // Each value differs from its default, so that a key not written would be seen.
        let defaults = Mirror(reflecting: Preferences.Values()).children.map { "\($0.value)" }
        for (child, base) in zip(Mirror(reflecting: values).children, defaults) { #expect("\(child.value)" != base, "\(child.label ?? "")") }
        #expect(Mirror(reflecting: values).children.count == Preferences.Values.CodingKeys.allCases.count)
        Preferences(home.places).change { $0 = values }
        #expect(Preferences(home.places).values == values)
    }

    /// The one copy each file has: the models of the window share it, so that one never undoes another's write.
    @Test func oneCopyPerFile() {
        let home = Home(prefix: "something-preferences-"), other = Home(prefix: "something-preferences-")
        defer { home.remove(); other.remove() }
        #expect(Preferences.at(home.places) === Preferences.at(home.places) && Preferences.at(home.places) !== Preferences.at(other.places))
        Preferences.at(home.places).assistant = "pi"
        Preferences.at(home.places).toured = true
        let read = Preferences(home.places)
        #expect(read.assistant == "pi" && read.toured)
    }

    /// Opening a space puts it first in the recent ones, at most ten; a space gone from the folder at the start leaves
    /// its group, the recent ones and its name, and its group stays; one moved to the Trash too.
    @Test func aSpaceRemovedOnDiskLeavesItsGroup() throws {
        let home = Home(prefix: "something-preferences-")
        defer { home.remove() }
        for name in ["garden", "pond", "shed"] { try home.space(name, page(nil, "")) }
        let preferences = Preferences(home.places)
        for name in (1...12).map({ "invented-\($0)" }) + ["pond", "garden", "pond"] { preferences.opened(name) }
        #expect(preferences.recents.prefix(3) == ["pond", "garden", "invented-12"] && preferences.recents.count == Preferences.recentLimit)
        preferences.change {
            $0.groups = [Preferences.Group(name: "Notes", spaces: ["garden", "pond"]), Preferences.Group(name: "Breaks", spaces: ["shed"])]
            $0.names = ["pond": "The pond", "shed": "Shed"]
        }
        try FileManager.default.removeItem(at: home.places.spaces.appendingPathComponent("pond.html"))
        preferences.forgetGone(in: home.places.spaces)
        #expect(preferences.groups == [Preferences.Group(name: "Notes", spaces: ["garden"]), Preferences.Group(name: "Breaks", spaces: ["shed"])])
        #expect(preferences.names == ["shed": "Shed"] && preferences.recents == ["garden"] && preferences.lastOpen == "pond")
        preferences.forget("shed")
        #expect(preferences.groups[1] == Preferences.Group(name: "Breaks", spaces: []) && preferences.names.isEmpty)
        preferences.forgetGone(in: home.places.spaces.appendingPathComponent("missing"))
        #expect(preferences.groups[0].spaces == ["garden"], "a folder that cannot be listed forgets nothing")
        #expect(Preferences(home.places).groups == preferences.groups)
    }
}
