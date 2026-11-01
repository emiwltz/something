// The three chips, everywhere an agent is chosen: its program, its model and effort, and what it does on its own, in
// the card, on New Space, in the panel and (the model alone) in Settings. One value, `ModelChoice`, says what the model
// chip edits wherever it stands, and the same picker opens from it (Picker.swift); a place only says how to read it and
// how to write it. Friendly names only: an id is never drawn. What cannot change is a plain chip, and says why.
import AppKit
import SomethingAgents
import SomethingCore
import SwiftUI

/// What the model chip edits and how it reads, one value in every place.
struct ModelChoice {
    /// One model: its name and line, `value` nil for the program's own choice where it lists no such row, and its
    /// provider in a long list.
    struct Row: Equatable {
        let value: String?, name: String
        var about: String? = nil, group: String? = nil
        var isDefault: Bool { value == nil || value == "default" }
    }
    /// What is known of its models: their rows, that it picks its own, that they are being read, or nothing yet.
    enum Models: Equatable { case rows, own, reading, unread }

    let name: String, models: Models
    /// The models as the program lists them, the rows drawn from them, and the value chosen.
    var list: [Option] = [], rows: [Row] = [], chosen: String? = nil
    /// The levels the gauge shows, the chosen one, and whether the agent has no list of them yet.
    var efforts: [Option] = [], effort: String? = nil, effortUnread = false
    /// The foot's words, whether it links to the defaults, and whether the chosen notch clicked again clears it.
    var scope = "", defaults = false, clears = false
    var pick: (String?) -> Void = { _ in }, pickEffort: (String) -> Void = { _ in }

    /// From this many rows a list has a search field and its providers' groups.
    static let long = 7

    /// What the model and the effort read now, by name, never an id.
    var words: (model: String, effort: String?) {
        (models == .own ? "Its own model" : chosen.map { Words.model($0, in: list) } ?? "Default model",
         models == .own ? nil : effort.map { e in efforts.first { $0.value == e }?.label ?? Option.effortLabels[e] ?? e.capitalized })
    }
    var chip: String { [words.model, words.effort].compactMap { $0 }.joined(separator: " · ") }
    var isLong: Bool { rows.count >= ModelChoice.long }
    /// The line beside MODEL: whose list this is, when it is the person's own setting rather than the program's.
    var from: String? {
        guard rows.contains(where: { $0.value?.contains("/") == true }) else { return nil }
        return isLong ? "From the providers set in \(name)" : "From " + Words.possessive(name) + " own settings"
    }
    func isChosen(_ row: Row) -> Bool { row.value == chosen || (chosen == nil && row.isDefault) }

    /// The rows of `models`, with the program's own choice first: `plain` adds one where the list has none. A value
    /// "provider/model" says its provider: a long list groups by it, a short one says it under the name.
    static func rows(_ models: [Option], name: String, plain: Bool) -> [Row] {
        let long = models.count + (plain ? 1 : 0) >= ModelChoice.long
        let rows = models.map { option -> Row in
            if option.value == "default" { return Row(value: option.value, name: option.label, about: "Follows " + Words.possessive(name) + " own choice") }
            let parts = option.label.split(separator: "/", maxSplits: 1).map(String.init), provider = option.value.split(separator: "/", maxSplits: 1).first.map(String.init)
            let group = parts.count > 1 ? parts[0] : option.value.contains("/") ? provider : nil
            return Row(value: option.value, name: parts.last ?? option.label, about: option.about ?? (long ? nil : group), group: long ? group : nil)
        }
        let own = Row(value: nil, name: "Default", about: "Follows " + Words.possessive(name) + " own choice")
        return plain && !rows.contains(where: \.isDefault) ? [own] + rows : rows
    }

    /// What the rows matching every word of `query` are.
    func shown(_ query: String) -> [Row] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return rows.filter { row in words.allSatisfy { [row.name, row.group ?? "", row.about ?? ""].joined(separator: " ").lowercased().contains($0) } }
    }
}

extension Options {
    /// The efforts that are levels. An effort with an `about` is the program's one beyond them (only a driver writes
    /// one, for that): it comes last in the gauge, apart, and stays with its conversation.
    var levels: [Option] { effort?.filter { $0.about == nil } ?? [] }
}

extension ModelChoice {
    /// The chip of an agent in a space's panel: its list as it gives it, its change going through `set`, which is how
    /// the panel reaches it.
    init(agent: Agent, set: @escaping (String?, String?) -> Void) {
        let name = Registry.app.name(of: agent.kind), list = agent.options.model ?? []
        self.init(name: name, models: list.isEmpty ? .unread : .rows, list: list, rows: ModelChoice.rows(list, name: name, plain: false), chosen: agent.model,
                  efforts: agent.can.effort ? agent.options.effort ?? [] : [], effort: agent.effort, scope: "For this agent · From its next turn",
                  pick: { set($0, nil) }, pickEffort: { set(nil, $0) })
    }

    /// Settings: what new spaces start with, from what the program last listed. Only levels: what is beyond them stays
    /// with a conversation. A gauge sets a level, so the chosen notch clicked again gives the agent's own back.
    init(defaultsOf kind: String, _ preferences: Preferences, reading: Bool) {
        let name = Registry.app.name(of: kind), limits = Registry.app.limits[kind] ?? [], listed = preferences.listed[kind], list = listed?.model ?? []
        self.init(name: name, models: limits.contains("model") ? .own : reading ? .reading : list.isEmpty ? .unread : .rows, list: list,
                  rows: ModelChoice.rows(list, name: name, plain: true), chosen: preferences.model,
                  efforts: limits.contains("effort") ? [] : listed?.levels ?? [], effort: preferences.effort, scope: "For new spaces", clears: true,
                  pick: { value in preferences.change { $0.model = value } },
                  pickEffort: { value in preferences.change { $0.effort = $0.effort == value ? nil : value } })
    }
}

extension AssistantModel {
    /// This conversation's model chip. Its own choice shows as a row only while nothing runs: a running agent has no
    /// way back to it but the row its list has. The choice comes first, since an agent reports a new model only with
    /// its next turn; an effort the running agent no longer offers is what it reports instead.
    var modelChoice: ModelChoice {
        let offered = offered, list = offered.model ?? [], kind = kind ?? "", running = awake(session)
        let known: ModelChoice.Models = ownModel ? .own : reading.contains(kind) ? .reading : list.isEmpty ? .unread : .rows
        var choice = ModelChoice(name: name, models: known, list: list, rows: ModelChoice.rows(list, name: name, plain: !running), chosen: session.model ?? agent?.model)
        if Registry.app.limits[kind]?.contains("effort") != true {
            choice.efforts = offered.effort ?? []
            choice.effortUnread = choice.efforts.isEmpty && !running
        }
        let gone = running && !choice.efforts.isEmpty && !choice.efforts.contains { $0.value == session.effort }
        choice.effort = gone ? agent?.effort : session.effort ?? agent?.effort
        choice.scope = (inSpace ? "For \(title) only" : "For this space only") + (working ? " · From its next turn" : "")
        choice.defaults = true
        (choice.pick, choice.pickEffort) = ({ [self] in chooseModel($0) }, { [self] in choose(effort: $0) })
        return choice
    }

    /// What the third chip says of this conversation: a rung that can change, or the program's own way, said plainly.
    var ownWords: String {
        AgentChips.fixed(kind) ?? (!canAskEverything ? "Its Own Settings" : askEverything ? "Asks First" : "Accepts Edits")
    }

    /// The third chip's menu, for a program whose building work is allowed ahead.
    var ownMenu: WordMenu? {
        guard canAskEverything else { return nil }
        let rows = [("Asks First", "It asks before each change and each command.", true), ("Accepts Edits", "Changes files in its folder without asking. Anything else asks you.", false)]
        return WordMenu(title: "On Its Own · From its next conversation", rows: rows.map { title, note, asks in
            WordMenu.Row(title: title, note: note, on: asks == askEverything) { [self] in if asks != askEverything { toggleAsking() } }
        })
    }
}

/// One chip's face: a monogram when it has one, its words, the chevron when it opens, the soft fill while it is open.
private struct ChipFace: View {
    var monogram: String? = nil, words: String? = nil, opens = true, open = false

    var body: some View {
        HStack(spacing: 6) {
            if let monogram { Monogram(name: monogram, side: 16) }
            if let words { Text(words).lineLimit(1).truncationMode(.tail) }
            if opens { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Look.Token.ink3.ui) }
        }
        .font(Look.font(.ui, size: 12, weight: .medium).ui).foregroundStyle((open ? Look.Token.ink : .ink2).ui)
        .padding(.leading, monogram == nil ? 8 : 4).padding(.trailing, opens ? 7 : 8).frame(height: 26)
        .background(open ? Look.Token.hover.ui : .clear, in: RoundedRectangle(cornerRadius: Look.control + 1))
        .contentShape(Rectangle())
    }
}

/// A chip that says and does nothing else: a program fixed while it runs, a way of asking that has no choice. `why` is
/// what the pointer and VoiceOver learn.
struct FixedChip: View {
    var monogram: String? = nil, words: String? = nil
    let why: String

    var body: some View { ChipFace(monogram: monogram, words: words, opens: false).help(why).accessibilityElement(children: .ignore).accessibilityLabel(why) }
}

/// The chip that opens a picker, its place kept for the picker (WordSpot: each pass's spot is the one in use).
private struct PickerChip: View {
    var monogram: String? = nil
    let words: String?, part: String, label: String
    let open: (NSView) -> Void
    var spot = WordSpot()

    var body: some View {
        let spot = spot, open = open
        Button { if let view = spot.view { open(view) } } label: { ChipFace(monogram: monogram, words: words, open: Popover.open.part == part) }
            .buttonStyle(.plain).fixedSize()
            .background(WordPlace(spot: spot))
            .accessibilityLabel(label)
            .accessibilityAddTraits(Popover.open.part == part ? .isSelected : [])
    }
}

/// The model chip over `choice`, read again at each drawing and by its picker.
struct ModelChip: View {
    let choice: () -> ModelChoice
    /// Called as it opens: a program never read has its models read now.
    var opening: () -> Void = {}

    var body: some View {
        let now = choice(), choice = choice, opening = opening
        PickerChip(words: now.chip.prefix(1).uppercased() + now.chip.dropFirst(), part: "model", label: ModelChip.label(now)) {
            opening()
            ModelChip.open(choice, from: $0)
        }
    }

    /// Opens the picker over `choice`, by the chip at `view`.
    static func open(_ choice: @escaping () -> ModelChoice, from view: NSView) {
        let keyboard = PickerKeys(choice)
        Popover.toggle(from: view, part: "model", keys: keyboard.press) { popover in
            ModelPicker(choice: choice, keyboard: keyboard, close: { popover?.close() })
        }
    }

    /// What VoiceOver reads on it.
    static func label(_ choice: ModelChoice) -> String { "Model: \(choice.chip). Change" }
}

/// The third chip: its menu of rungs, or its words alone when there is nothing to choose.
struct OwnChip: View {
    let words: String
    var menu: WordMenu? = nil
    var spot = WordSpot()

    var body: some View {
        if let menu {
            let spot = spot
            Button { spot.open(menu) } label: { ChipFace(words: words) }
                .buttonStyle(.plain).fixedSize().background(WordPlace(spot: spot))
                .accessibilityLabel("On Its Own: \(words). Change")
        } else {
            FixedChip(words: words, why: "On Its Own: \(words)")
        }
    }
}

/// An assistant's chips: its program, which a person may change, its model and effort, and what it does on its own.
/// `compact` draws the program by its monogram alone; without `own` the third chip stays away (the welcome's).
struct AgentChips: View {
    let model: AssistantModel
    var compact = false, own = true

    /// Opens the programs' picker of `model`, by the chip at `view`.
    static func open(_ model: AssistantModel, from view: NSView) {
        let keyboard = PickerKeys(model)
        Popover.toggle(from: view, part: "program", keys: keyboard.press) { popover in ProgramPicker(model: model, keyboard: keyboard, close: { popover?.close() }) }
    }

    /// The third chip's words for a program with no choice to give; nil for any other.
    static func fixed(_ kind: String?) -> String? {
        let agent = kind.flatMap(Registry.app.agent)
        return agent?.neverAsks == true ? "Never asks, by design." : agent?.asksNothingByDefault == true ? "Never asks by default." : kind == nil ? "" : nil
    }

    /// What VoiceOver reads on the three chips.
    static func labels(_ model: AssistantModel) -> [String] {
        ["Program: \(model.name). Change", ModelChip.label(model.modelChoice), "On Its Own: \(model.ownWords)" + (model.ownMenu == nil ? "" : ". Change")]
    }

    var body: some View {
        HStack(spacing: 2) {
            PickerChip(monogram: model.name, words: compact ? nil : model.name, part: "program", label: AgentChips.labels(model)[0]) { AgentChips.open(model, from: $0) }
            ModelChip(choice: { model.modelChoice }, opening: { model.readModels() })
            if own { OwnChip(words: model.ownWords, menu: model.ownMenu) }
        }
        .disabled(model.blocked).opacity(model.blocked ? 0.55 : 1)
    }
}

/// A running agent's chips on its row: its program, fixed while it runs, its model and what it does on its own. `agent`
/// reads it now: its picker stays up through a pick.
struct RowChips: View {
    let agent: () -> Agent, set: (_ model: String?, _ mode: String?, _ effort: String?) -> Void

    var body: some View {
        let agent = agent, set = set, now = agent(), name = Registry.app.name(of: now.kind)
        let choice = { ModelChoice(agent: agent()) { model, effort in set(model, nil, effort) } }
        HStack(spacing: 2) {
            FixedChip(monogram: name, why: "\(name), fixed while it runs")
            if now.can.model, now.options.model?.isEmpty == false { ModelChip(choice: choice) }
            else { FixedChip(words: choice().chip, why: now.because["model"] ?? "\(name) chooses its own") }
            if let words = AgentChips.fixed(now.kind) { OwnChip(words: words) }
            else if now.can.mode, let modes = now.options.mode, !modes.isEmpty {
                OwnChip(words: modes.first { $0.value == now.mode }?.label ?? "Its Own Settings", menu: WordMenu(title: "On Its Own · From its next turn", rows: modes.map { mode in
                    WordMenu.Row(title: mode.label, on: mode.value == now.mode) { set(nil, mode.value, nil) }
                }))
            } else { OwnChip(words: "Its Own Settings") }
        }
    }
}
