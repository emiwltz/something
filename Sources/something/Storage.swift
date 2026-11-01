// Settings › Spaces: where the spaces live, whether an export carries their memory, how many versions each keeps,
// whether a new space's words bring a few questions first, and what something keeps weighs against the storage limit,
// in three parts (the spaces' versions, their memory, the spaces themselves), measured off the main queue because a
// store of spaces can hold thousands of files. Past the limit the oldest versions go first (Versions); spaces and their
// memory are never removed here.
import AppKit
import SomethingCore
import SwiftUI

/// What the store weighs, in bytes.
struct Storage: Equatable {
    /// Application Support/something/versions, ~/something/data and ~/something/spaces.
    var versions: Int, memory: Int, spaces: Int
    var used: Int { versions + memory + spaces }

    /// The storage limits one may choose, in megabytes, and how each is said.
    static let limits = [(250, "250 MB"), (500, "500 MB"), (1_000, "1 GB"), (2_000, "2 GB")]

    /// The store of `places` weighed now; reads files only, and is meant for a queue other than the main one.
    @Sendable static func weigh(_ places: Places) -> Storage {
        Storage(versions: bytes(places.versions), memory: bytes(places.data), spaces: bytes(places.spaces))
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
}

extension SettingsModel {
    /// Weighs the store off the main queue, then shows it.
    func measure() {
        let (places, weigh) = (places, weigh)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let storage = weigh(places)
            DispatchQueue.main.async { self?.storage = storage }
        }
    }

    /// Spaces: where they live, the export's memory and the versions kept, the questions first, then the store's weight against its limit.
    func storageSections() -> [SettingsSection] {
        let spaces = places.spaces
        return [
            SettingsSection(title: "", rows: [
                // The places' home is the person's: ~ stands for it, whatever home a trial gives.
                SettingsRow(title: "Where they live", note: "`~/\(Spaces.folders.spaces)` · one HTML file or folder each, yours.",
                            control: .button("Show in Finder", symbol: "finder") { [weak self] in self?.reveal(spaces) }),
                SettingsRow(title: "Include a space’s memory when you export it",
                            note: "Ticks Include Its Memory in File › Export Space… (⇧⌘E). Off: a file you hand to someone carries nothing it remembers.", control: toggle(\.exportMemory)),
                SettingsRow(title: "Keep", note: "Each change is a version. ⌘Z goes back one; View › Show History… shows the others.",
                            control: number(\.versionsKept, [(20, "20"), (50, "50"), (100, "100"), (0, "All of them")]), trail: "versions of each space"),
            ]),
            SettingsSection(title: "New spaces", rows: [
                SettingsRow(title: "Ask me a few questions first", note: "A few short choices before a build, all skippable. Off: Build starts at once.", control: toggle(\.askFirst)),
            ]),
            SettingsSection(title: "Storage", rows: [SettingsRow(title: "Storage limit", note: "", control: number(\.storageLimit, Storage.limits))], block: .storage),
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
                Text("Limit").font(Look.font(.ui, size: 12).ui).foregroundStyle(Look.Token.ink3.ui)
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
    }

    static let tones: [Look.Token] = [.ink, .ink2, .ink3]

    private var parts: [(String, Int?)] {
        [("Versions", storage?.versions), ("Memory", storage?.memory), ("Spaces", storage?.spaces)]
    }

    /// The limit as its choice says it.
    private var limitLabel: String { Storage.limits.first { $0.0 == megabytes }?.1 ?? "\(megabytes) MB" }

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
