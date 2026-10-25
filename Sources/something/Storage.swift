// Settings › Versions & Storage: how many versions each space keeps, and what something keeps weighs against the
// storage limit, in three parts (the spaces' versions, their memory, the spaces themselves), measured off the main
// queue because a store of spaces can hold thousands of files. Clear Old Versions drops the versions older than 30
// days, each space keeping its 10 latest, and only after the person's click on the alert's Clear Versions: it cannot be
// undone. Spaces and their memory are never removed here.
import AppKit
import SomethingCore
import SwiftUI

/// What the store weighs, in bytes, and what Clear Old Versions would free.
struct Storage: Equatable {
    /// Application Support/something/versions, ~/something/data and ~/something/spaces.
    var versions: Int, memory: Int, spaces: Int
    var old: Versions.Old
    var used: Int { versions + memory + spaces }

    /// Clear Old Versions takes the versions older than `days`, each space keeping its `latest` newest.
    static let days = 30, latest = 10

    /// The storage limits one may choose, in megabytes, and how each is said.
    static let limits = [(250, "250 MB"), (500, "500 MB"), (1_000, "1 GB"), (2_000, "2 GB")]

    /// How a limit of `megabytes` is said: as its choice says it.
    static func label(_ megabytes: Int) -> String { limits.first { $0.0 == megabytes }?.1 ?? "\(megabytes) MB" }

    /// The versions Clear Old Versions takes are those before this date.
    static func cutoff(_ now: Date) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    /// The store of `places` weighed at `now`; reads files only, and is meant for a queue other than the main one.
    @Sendable static func weigh(_ places: Places, now: Date) -> Storage {
        Storage(versions: bytes(places.versions), memory: bytes(places.data), spaces: bytes(places.spaces),
                old: Versions(root: places.versions, keep: 0, limit: 0).old(before: cutoff(now), keeping: latest))
    }

    /// The bytes of the regular files under `folder`, hidden ones included and links not followed; 0 when it is not
    /// there.
    static func bytes(_ folder: URL) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        return walk.reduce(0) { total, item in
            guard let url = item as? URL, let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return total }
            return total + (values.fileSize ?? 0)
        }
    }

    /// Bytes in whole megabytes, as the mockup says them: "312 MB"; a few bytes are not said as none.
    static func megabytes(_ bytes: Int) -> String {
        let whole = Int((Double(bytes) / 1_000_000).rounded())
        return whole == 0 && bytes > 0 ? "less than 1 MB" : "\(whole) MB"
    }

    /// The alert before Clear Old Versions: Cancel holds the focus and Escape; Clear Versions is never pressed by Return.
    static func alert(_ old: Versions.Old) -> Sheet {
        let spaces = old.spaces == 1 ? "1 space" : "\(old.spaces) spaces"
        let sheet = Sheet(icon: .sign, title: "Clear versions older than \(days) days?",
                          body: [("This removes \(megabytes(old.bytes)) of versions from \(spaces). Each space keeps its \(latest) latest versions. This can’t be undone.", false)],
                          actions: [.init(title: "Cancel", role: .cancel), .init(title: "Clear Versions", role: .destructive)], alert: true, width: 280)
        return sheet
    }

    /// Hangs the alert from the Settings window and runs `then` only on Clear Versions.
    @MainActor static func confirm(_ old: Versions.Old, then: @escaping () -> Void) {
        guard let window = Settings.shown?.window, window.attachedSheet == nil else { return }
        alert(old).hang(on: window) { if $0 == .destructive { then() } }
    }
}

extension SettingsModel {
    /// Weighs the store off the main queue, then shows it.
    func measure() {
        let (places, weigh, now) = (places, weigh, clock())
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let storage = weigh(places, now)
            DispatchQueue.main.async { self?.storage = storage }
        }
    }

    /// Clear Old Versions…: asks first; on Clear Versions, drops them, says what was freed and weighs again. On the
    /// main queue, as a version is taken there: none can be written between the read and the write of an index. What
    /// the alert says is read again at the click, as Settings may have stayed open for days since it was weighed; one
    /// cutoff serves the alert and the clearing, and the line says what was really dropped.
    func clearOld() {
        let store = Versions(root: places.versions, keep: 0, limit: 0), cutoff = Storage.cutoff(clock())
        let old = store.old(before: cutoff, keeping: Storage.latest)
        guard old.bytes > 0 else { return measure() }
        confirm(old) { [weak self] in
            guard let self else { return }
            let dropped = store.clear(before: cutoff, keeping: Storage.latest)
            cleared = "Cleared \(Storage.megabytes(dropped.bytes)) of versions older than \(Storage.days) days."
            measure()
        }
    }

    /// Versions & Storage: versions kept per space, then the store's weight against its limit, Clear Old Versions and
    /// where the spaces are.
    func storageSections() -> [SettingsSection] {
        let spaces = places.spaces
        let old = storage?.old.bytes ?? 0
        return [
            SettingsSection(title: "Versions", rows: [
                SettingsRow(title: "Keep", note: "Each change your assistant makes is a version. ⌘Z goes back one; the older ones stay in History (Space › Show History…).",
                            control: number(\.versionsKept, [(20, "20"), (50, "50"), (100, "100"), (0, "All of them")]), trail: "versions per space"),
            ]),
            SettingsSection(title: "Storage", rows: [
                SettingsRow(title: "Storage limit", note: "", control: number(\.storageLimit, Storage.limits)),
                SettingsRow(title: "When it is full", note: "The oldest versions go first. Your spaces and their memory are never removed.",
                            control: .button("Clear Old Versions…", enabled: old > 0) { [weak self] in self?.clearOld() }),
                // The places' home is the person's: ~ stands for it, whatever home a trial gives.
                SettingsRow(title: "Where", note: "~/" + Spaces.folders.spaces,
                            control: .button("Show in Finder", symbol: "finder") { [weak self] in self?.reveal(spaces) }, code: true),
            ], storage: true, foot: cleared),
        ]
    }
}

/// The store's weight: the megabytes used of the limit and the limit's choice, a bar of the three parts against the
/// limit, and their legend with what is free.
struct StorageBlock: View {
    let storage: Storage?
    /// The limit in megabytes, and its row, which only draws the menu that changes it.
    let megabytes: Int
    let limit: SettingsRow

    var body: some View {
        let total = megabytes * 1_000_000
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let storage {
                    Text(Storage.megabytes(storage.used)).font(Look.font(.title, size: 22, weight: .semibold).ui).kerning(-0.44).foregroundStyle(Look.Token.ink.ui)
                    Text("used of \(limitLabel)").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                } else {
                    Text("Measuring…").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
                }
                Spacer(minLength: 0)
                RowControl(row: limit).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .frame(minHeight: 26)
            bar(total)
            HStack(spacing: 16) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in legend(part.0, part.1, Self.tones[index]) }
                legend("Free", storage.map { max(0, total - $0.used) }, nil)
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    static let tones: [Look.Token] = [.ink, .ink2, .ink3]

    private var parts: [(String, Int?)] {
        [("Versions", storage?.versions), ("Memory", storage?.memory), ("Spaces", storage?.spaces)]
    }

    private var limitLabel: String { Storage.label(megabytes) }

    /// Ten points high in sunk inside a ring of line, each part's width its share of the limit (of what is used, when
    /// more than the limit is), two points between them.
    private func bar(_ total: Int) -> some View {
        let whole = Double(max(total, storage?.used ?? 0, 1))
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return GeometryReader { space in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Self.tones[index].ui.frame(width: max(0, space.size.width * Double(part.1 ?? 0) / whole))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10).background(Look.Token.sunk.ui).clipShape(shape).overlay(shape.strokeBorder(Look.Token.line.ui))
        .accessibilityElement().accessibilityLabel(storage.map { "\(Storage.megabytes($0.used)) used of \(limitLabel)" } ?? "Measuring")
    }

    /// One part of the legend: its square in its tone (Free a ringed sunk one), its name, and its megabytes.
    private func legend(_ name: String, _ bytes: Int?, _ tone: Look.Token?) -> some View {
        let square = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return HStack(spacing: 6) {
            Group {
                if let tone { square.fill(tone.ui) } else { square.fill(Look.Token.sunk.ui).overlay(square.strokeBorder(Look.Token.line2.ui)) }
            }
            .frame(width: 8, height: 8)
            Text(name).foregroundStyle(Look.Token.ink2.ui)
            Text(bytes.map(Storage.megabytes) ?? "—").foregroundStyle(Look.Token.ink3.ui)
        }
        .font(Look.small.font.ui)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(name) \(bytes.map(Storage.megabytes) ?? "unknown")")
    }
}
