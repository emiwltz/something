// The tour (plan B.4), shown in the window at the first start and again from Help › Welcome Tour: Welcome, then who
// builds with you, then the blank page itself, where it ends. It never starts an agent: choosing a builder only says
// which one the first message will start. Its end is kept in window.json, with whether it offered the launcher.
import SwiftUI

@Observable final class Tour {
    /// What the tour shows: the welcome, the builders found, none found, or the search still going on.
    enum Screen: Equatable { case welcome, builders, none, looking }

    /// 0 for the welcome, 1 for who builds with you.
    var step = 0
    /// Whether the welcome offers to add something to Applications, and whether its box is ticked.
    let offersLauncher: Bool
    var addLauncher = true
    /// Called when the tour ended, with what went wrong when the launcher could not be made.
    @ObservationIgnored var finished: (_ problem: String?) -> Void = { _ in }
    let places: Places, app: URL

    /// The tour of the something.app at `app`, whose place says whether it offers the launcher.
    init(places: Places, app: URL = Bundle.main.bundleURL) {
        (self.places, self.app) = (places, app)
        offersLauncher = Launcher.offered(app: app, places: places)
    }

    /// Ends the tour: it is not shown again at the next start, nor the launcher offered again; the launcher is made
    /// when the box was ticked.
    func end() {
        Library.WindowFile.update(places) { [offersLauncher] in
            $0.toured = true
            if offersLauncher { $0.launcherOffered = true }
        }
        guard offersLauncher, addLauncher, let prefix = Launcher.prefix(of: app) else { return finished(nil) }
        do {
            try Launcher.make(prefix: prefix, places: places, icon: Bundle.main.url(forResource: "something", withExtension: "icns"))
            finished(nil)
        } catch { finished(error.sentence) }
    }

    func screen(_ assistant: AssistantModel) -> Screen {
        if step == 0 { return .welcome }
        if assistant.noAgent { return .none }
        return assistant.kind == nil ? .looking : .builders
    }
}

struct TourView: View {
    @Bindable var tour: Tour
    let assistant: AssistantModel

    var body: some View {
        VStack(spacing: 14) {
            switch tour.screen(assistant) {
            case .welcome: welcome
            case .builders: builders
            case .none: none
            case .looking:
                ProgressView().controlSize(.small)
                Text("Looking for coding agents on your Mac…").foregroundStyle(.secondary)
                buttons { Button("Back") { tour.step = 0 } }
            }
        }
        .frame(width: 560)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            HStack(spacing: 7) {
                ForEach(0..<2) { Circle().fill(tour.step == $0 ? Color.secondary : Color.secondary.opacity(0.3)).frame(width: 7, height: 7) }
            }
            .padding(.bottom, 26)
            .accessibilityElement()
            .accessibilityLabel("Step \(tour.step + 1) of 2")
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 30, weight: .bold)).padding(.top, 6)
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }.controlSize(.large).padding(.top, 10)
    }

    private var welcome: some View {
        Group {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            title("Welcome to something")
            Text("Make your own spaces: pages built for you by your coding agent, shown safely here.")
                .font(.system(size: 17, weight: .medium))
            Grid(alignment: .leading, verticalSpacing: 8) {
                ForEach([("text.bubble", "You describe it. Your agent builds it."), ("hand.raised", "something shows it, and asks you before anything sensitive."),
                         ("lock", "Nothing leaves your Mac: no account, no tracking.")], id: \.0) { line in
                    GridRow { Image(systemName: line.0).gridColumnAlignment(.center); Text(line.1) }
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            if tour.offersLauncher {
                Toggle("Add something to Applications, so Spotlight finds it.", isOn: $tour.addLauncher)
                    .foregroundStyle(.secondary)
            }
            buttons { Button("Continue") { tour.step = 1 }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
    }

    private var builders: some View {
        Group {
            title("Who builds with you?")
            Text("These coding agents are on your Mac. Choose the one that builds your spaces.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(assistant.entries) { entry in
                    Button { assistant.choose(entry.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.checked ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(entry.checked ? Color.accentColor : .secondary)
                            Text(entry.title)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!entry.enabled)
                    .help(entry.note ?? "")
                    if entry.id != assistant.entries.last?.id { Divider() }
                }
            }
            .multilineTextAlignment(.leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(width: 420)
            Text(assistant.firstLines[0]).font(.system(size: 12.5)).foregroundStyle(.secondary).frame(width: 420)
            Text("It uses your own account and settings, as in Terminal. Nothing starts until you send it a first message.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.top, 6)
            buttons {
                Button("Back") { tour.step = 0 }
                Button("Continue") { tour.end() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    private var none: some View {
        Group {
            title("No coding agent yet")
            let names = InstallList.builders.map(\.name)
            Text("something builds spaces with \(names.dropLast().joined(separator: ", ")) or \(names.last ?? ""). Install one, sign it in once in Terminal, then click Look Again.")
                .foregroundStyle(.secondary)
            InstallList(rows: InstallList.builders, copy: assistant.copy).multilineTextAlignment(.leading).padding(.top, 6)
            buttons {
                Button("Continue Without an Agent") { tour.end() }
                Button("Look Again") { assistant.engine.lookAgain() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }
}
