// History: the open space's versions, the panel's third tab (Inspector.swift), at the same width. Each row is a version: the page's picture, the sentence that made it, when and who; the
// newest says Now. A change no turn claims reads "Edited outside something", with a pencil, and the newest such edit
// also says what it changed in its files; the first capture of the space, while it is still kept, is the space as
// something first kept it, never an edit on disk. Six rows show (seven when the newest is that edit), then a row that
// unfolds the older ones. History opens on the version before the newest. Restore This Version brings the chosen one
// back through Changes, where the restore is itself a version, undone by ⌘Z, and refused while an assistant works on
// that space. ↑ and ↓ move the choice while the focus is in the panel. A version's picture is taken once its page
// settled, when the page shows exactly its files. Holding a row 260 ms, or Space, shows that version over the page
// until it is let go (Glimpse.swift).
import AppKit
import Observation
import SomethingCore
import SwiftUI
import WebKit

@Observable final class History {
    @ObservationIgnored let places: Places
    /// The clock the times are said by: Info's.
    @ObservationIgnored var clock: () -> Date = Date.init
    /// Brings the space `name` back to a version, named in words ("the version of Today 18:12"): Changes'.
    @ObservationIgnored var restoring: (_ name: String, _ version: Versions.Version, _ words: String) -> Void = { _, _, _ in }
    /// The open space's view, over which a held version shows, and where a failure is said: Info's.
    @ObservationIgnored var current: () -> SpaceView? = { nil }
    @ObservationIgnored var tell: (String) -> Void = { _ in }
    /// The version held over the page, while it is.
    @ObservationIgnored private(set) var glimpse: Glimpse?
    /// Whether the chosen version shows over the page: its row is ringed.
    private(set) var comparing = false
    /// The pointer down on a row, until it is held long enough or let go.
    @ObservationIgnored private var pressing: DispatchWorkItem?
    private(set) var space: Space?
    /// Its versions, newest first, and what they weigh in the store.
    private(set) var versions: [Versions.Version] = []
    private(set) var bytes = 0
    /// The chosen version, by id; Restore This Version brings it back.
    var chosen: String?
    /// Whether the versions past the rows shown show.
    var unfolded = false
    /// The row under the pointer.
    var hovered: String?
    /// The versions whose picture is being taken.
    @ObservationIgnored private var taking: Set<String> = []
    /// The pictures read so far, by version id: rows are drawn again at each hover, the files read once.
    @ObservationIgnored private var images: [String: NSImage] = [:]

    /// How many rows show before the older ones fold; how long a row is held before its version shows.
    static let first = 6, hold = 0.26

    init(places: Places) { self.places = places }

    /// The store, read only here: limits apply when a version is kept.
    var store: Versions { Versions(root: places.versions, keep: 0, limit: 0) }

    /// Shows the versions of `space`, or none. Another space starts on the version before the newest, as History
    /// opens to compare or restore; the same one keeps its choice while that version is still kept.
    func show(_ space: Space?) {
        let other = space?.name != self.space?.name, listed = space.map { store.list($0.name) } ?? []
        if other { closed() }
        self.space = space
        // The store is walked for its weight only when what it holds changed.
        if other || listed != versions { bytes = space.map { store.weight($0.name) } ?? 0 }
        versions = listed
        if other { images = [:] }
        if other || !versions.contains(where: { $0.id == chosen }) { opened() }
    }

    /// The panel opens: on the version before the newest, to compare or restore, the older ones folded.
    func opened() {
        chosen = versions.dropFirst().first?.id ?? versions.first?.id
        unfolded = false
    }

    /// A version of `name` was kept or restored: read again, the newest chosen.
    func kept(_ name: String) {
        guard space?.name == name else { return }
        show(space)
        chosen = versions.first?.id
    }

    /// Show What Changed: chooses the version kept just before the edit `id`, while both are still kept; a turn or a
    /// restore since then does not move the choice to another pair.
    func choose(before id: String) {
        guard let at = versions.firstIndex(where: { $0.id == id }), at + 1 < versions.count else { return }
        if at + 1 >= shown { unfolded = true }
        chosen = versions[at + 1].id
    }

    /// How many rows show before the older ones fold: six, plus the newest when `detail` describes it, an edit outside
    /// something added on top without pushing a row into the fold.
    var shown: Int { History.first + (versions.first.flatMap(detail) == nil ? 0 : 1) }

    /// The rows shown: the first ones, or all once unfolded.
    var rows: [Versions.Version] { unfolded ? versions : Array(versions.prefix(shown)) }

    /// Moves the choice `by` rows, unfolding the older versions when it goes past the last row shown.
    func move(_ by: Int) {
        guard !versions.isEmpty else { return }
        let at = versions.firstIndex { $0.id == chosen } ?? 0, next = max(0, min(versions.count - 1, at + by))
        if next >= shown { unfolded = true }
        chosen = versions[next].id
        if comparing { compare(true) }
    }

    /// Shows the chosen version over the open page (`on`), or the page as it is now. The newest is what the page
    /// shows: holding it shows nothing.
    func compare(_ on: Bool) {
        guard on, let space, let version = versions.first(where: { $0.id == chosen }), version.id != versions.first?.id,
              let open = current(), open.space.name == space.name, open.pointable else {
            glimpse?.release()
            (glimpse, comparing) = (nil, false)
            return
        }
        guard glimpse?.version.id != version.id else { return }
        glimpse?.release()
        do {
            glimpse = try Glimpse(version, over: open, store: store, words: title(version), when: History.when(version.when, now: clock()))
            comparing = true
        } catch {
            (glimpse, comparing) = (nil, false)
            tell(error.sentence)
        }
    }

    /// The pointer went down on the row `id`: held `hold` seconds, its version is chosen and shown over the page.
    func press(_ id: String) {
        guard pressing == nil else { return }
        let held = DispatchWorkItem { [weak self] in
            self?.pressing = nil
            self?.chosen = id
            self?.compare(true)
        }
        pressing = held
        DispatchQueue.main.asyncAfter(deadline: .now() + History.hold, execute: held)
    }

    /// The pointer went up: the page as it is now.
    func lift() {
        pressing?.cancel()
        pressing = nil
        compare(false)
    }

    /// History closed, or shows another space: nothing is held any more, and the copy of the last one held goes.
    func closed() {
        lift()
        if let space { Glimpse.remove(store, space.name) }
    }

    /// Restore This Version: the chosen one, unless it is the newest (what the space is now).
    func restore() {
        guard let space, let version = versions.first(where: { $0.id == chosen }), version.id != versions.first?.id else { return }
        restoring(space.name, version, "the version of " + History.when(version.when, now: clock()))
    }

    /// Whether Restore This Version can act: a version other than the newest is chosen.
    var restorable: Bool { chosen != nil && chosen != versions.first?.id }

    /// The row's first line: the sentence, quoted; "Edited outside something"; the space as something first kept it;
    /// or what a restore brought back.
    func title(_ version: Versions.Version) -> String {
        switch version.kind {
        case .turn, .quick: return "“\(version.sentence ?? "")”"
        case .outside: return version.first == true ? "As something first kept it" : "Edited outside something"
        case .restore:
            let back = versions.first { $0.id == version.restored }
            return back.map { "Restored the version of " + History.when($0.when, now: clock()) } ?? "Restored an older version"
        }
    }

    /// The row's second line: when, then who; for an edit no turn claims, that nobody here made it.
    func byline(_ version: Versions.Version) -> String {
        let who = version.kind != .outside ? version.who ?? "" : version.first == true ? "Before its first change here"
            : "Changed on disk, not by its assistant"
        return History.when(version.when, now: clock()) + " · " + who
    }

    /// What the newest version changed, when it is an edit outside something: "brief.html · one line added.
    /// something kept the version before it."; nil for any other row. The page's own column cannot be named: only its
    /// files are compared.
    func detail(_ version: Versions.Version) -> String? {
        guard version.kind == .outside, version.first != true, version.id == versions.first?.id, !version.summary.isEmpty else { return nil }
        return version.summary + ". something kept the version before it."
    }

    /// The fold's words: "6 older versions, back to 12 October"; nil when nothing folds.
    var older: String? {
        guard !unfolded, versions.count > shown, let oldest = versions.last else { return nil }
        let count = versions.count - shown, format = DateFormatter()
        (format.locale, format.dateFormat) = (Locale(identifier: "en_US_POSIX"), "d MMMM")
        return "\(count) older version\(count == 1 ? "" : "s"), back to \(format.string(from: oldest.when))"
    }

    /// "Today 18:12", "Yesterday 21:05", "Tuesday 11:02" within the week, "12 Oct 09:20", "12 Oct 2025 09:20".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        (format.locale, format.calendar, format.timeZone) = (Locale(identifier: "en_US_POSIX"), calendar, calendar.timeZone)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        format.dateFormat = switch days {
        case 0: "'Today' HH:mm"
        case 1: "'Yesterday' HH:mm"
        case 2...6: "EEEE HH:mm"
        default: calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM HH:mm" : "d MMM yyyy HH:mm"
        }
        return format.string(from: date)
    }

    /// The picture of a version, nil while none was taken.
    func picture(_ version: Versions.Version) -> NSImage? {
        guard let space, version.thumb != nil else { return nil }
        if let image = images[version.id] { return image }
        let image = NSImage(contentsOf: store.picture(space.name, version.id))
        images[version.id] = image
        return image
    }

    /// Takes the picture of `view`'s newest version once its page settled (its fonts, then a moment), when it has none
    /// and the page shows exactly its files. Returns whether one was kept.
    @MainActor @discardableResult func picture(of view: SpaceView) async -> Bool {
        let name = view.space.name, store = store, loads = view.loads
        // Only the space History shows; its files are read and hashed last, the cheaper checks first.
        guard space?.name == name, view.blocked.isEmpty, !view.stopped, let frame = view.frame, let newest = store.list(name).first, newest.thumb == nil,
              !taking.contains(newest.id), store.holds(view.space, newest) else { return false }
        taking.insert(newest.id)
        defer { taking.remove(newest.id) }
        _ = try? await view.web.callAsyncJavaScript("await document.fonts.ready; await new Promise((done) => setTimeout(done, 300))",
                                                    arguments: [:], in: frame, contentWorld: .defaultClient)
        guard view.loads == loads, view.frame != nil else { return false }
        let snapshot = WKSnapshotConfiguration(), width = view.web.bounds.width
        snapshot.rect = CGRect(x: 0, y: 0, width: width, height: min(view.web.bounds.height, width * 42 / 58))
        snapshot.snapshotWidth = 116
        guard let image = try? await view.web.takeSnapshot(configuration: snapshot), let png = CheckPage.png(image),
              (try? store.keep(picture: png, of: newest.id, in: name)) != nil else { return false }
        if space?.name == name { show(space) }
        return true
    }
}

/// The History panel: the header, the versions, and Hold Space to compare beside Restore This Version.
struct HistoryView: View {
    @Bindable var history: History
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            DockHeader(title: "History", sub: "\(title) · \(history.versions.count) version\(history.versions.count == 1 ? "" : "s") · \(Size.words(history.bytes))")
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 1) {
                        if history.versions.isEmpty {
                            Text("No version yet. Each change your assistant makes is kept here, named by what you asked.")
                                .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                        }
                        ForEach(history.rows) { row($0).id($0.id) }
                        if let older = history.older {
                            Button { history.unfolded = true } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "clock").font(.system(size: 11))
                                    Text(older).font(Look.small.font.ui)
                                }
                                .foregroundStyle(Look.Token.ink3.ui).padding(.horizontal, 10).padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
                .onChange(of: history.chosen) { _, chosen in if let chosen { scroller.scrollTo(chosen) } }
            }
            .accessibilityElement(children: .contain).accessibilityLabel("Versions")
            footer
        }
    }

    private func row(_ version: Versions.Version) -> some View {
        let chosen = version.id == history.chosen, outside = version.kind == .outside && version.first != true
        return Button { history.chosen = version.id } label: {
            HStack(alignment: .center, spacing: 11) {
                thumb(version, pencil: outside)
                VStack(alignment: .leading, spacing: 2) {
                    Text(history.title(version))
                        .font(outside ? Font(Look.oblique(Look.font(.ui, size: 12.5, weight: .medium))) : Look.font(.ui, size: 12.5, weight: .semibold).ui)
                        .foregroundStyle((outside ? Look.Token.ink2 : .ink).ui).lineLimit(2).lineSpacing(0.5)
                    Text(history.byline(version)).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(2)
                    if let detail = history.detail(version) {
                        Text(detail).font(Look.font(.ui, size: 11).ui).foregroundStyle(Look.Token.ink2.ui).lineSpacing(1.5).padding(.top, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if version.id == history.versions.first?.id {
                    Text("NOW").font(Look.font(.ui, size: 10, weight: .semibold).ui).kerning(0.4).foregroundStyle(Look.Token.ink2.ui)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Look.Token.line2.ui))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 2)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7 * Look.density)
            .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Look.Token.sel.ui : history.hovered == version.id ? Look.Token.hover.ui : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Look.Token.ink.ui, lineWidth: 1.5).opacity(chosen && history.comparing ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in history.press(version.id) }.onEnded { _ in history.lift() })
        .onHover { history.hovered = $0 ? version.id : history.hovered == version.id ? nil : history.hovered }
        .accessibilityLabel(history.title(version) + ", " + history.byline(version) + (history.detail(version).map { ", " + $0 } ?? "") + (version.id == history.versions.first?.id ? ", now" : ""))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The page's picture, 58 by 42, or its blank while none was taken; a pencil on an edit outside something.
    private func thumb(_ version: Versions.Version, pencil: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return ZStack(alignment: .bottomTrailing) {
            if let image = history.picture(version) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill).frame(width: 58, height: 42, alignment: .top)
            } else {
                Look.Token.bg2.ui.frame(width: 58, height: 42)
            }
            if pencil {
                Image(systemName: "pencil").font(.system(size: 9, weight: .semibold)).foregroundStyle(Look.Token.actfg.ui)
                    .frame(width: 17, height: 17).background(Circle().fill(Look.Token.act.ui)).padding(2)
            }
        }
        .frame(width: 58, height: 42).clipShape(shape).overlay(shape.strokeBorder(Look.Token.line2.ui))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("Hold")
                Text("Space").font(Look.font(.ui, size: 10.5, weight: .medium).ui).foregroundStyle(Look.Token.ink.ui)
                    .padding(.horizontal, 5).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(Look.Token.sel.ui))
                Text("to compare")
            }
            .font(Look.small.font.ui).foregroundStyle(Look.Token.ink3.ui).lineLimit(1).layoutPriority(-1)
            .accessibilityElement(children: .ignore).accessibilityLabel("Hold Space to compare")
            Spacer(minLength: 0)
            Button { history.restore() } label: { Text("Restore This Version").font(Look.font(.ui, size: 12.5, weight: .medium).ui) }
                .buttonStyle(Secondary(height: 30, leading: 11, trailing: 11)).fixedSize().disabled(!history.restorable).opacity(history.restorable ? 1 : 0.4)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 12))
        .overlay(alignment: .top) { Rectangle().fill(Look.Token.line.ui).frame(height: 1) }
    }
}
