// The blank page (plan B.4), the center when no space is open: New Space (⌘N), and where the tour ends. "What do you
// want to make?", the assistant's input made big, three suggestions that each send a whole sentence, the templates,
// each used by a click, and "Skip for now", which shows them all. Without a coding agent, the notice takes the input's
// place.
import SwiftUI

struct BlankView: View {
    /// Each suggestion and the sentence it sends.
    static let chips = [
        ("Who is waiting for me", "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can."),
        ("A morning brief of my agents", "Make me a space like a morning newspaper: what each of my agents did since yesterday."),
        ("A small game for my breaks", "Make me a small game I can play in a minute between two tasks, with my best score kept."),
    ]

    @Bindable var model: AssistantModel

    /// The input and what is said under it, kept in sight above the conversation.
    static let input = "input"

    /// The templates' columns in `width`: six when they fit, else three, two or one, so that every row is full.
    static func columns(_ width: CGFloat) -> Int {
        [6, 3, 2].first { (n: Int) -> Bool in CGFloat(n) * 148 + CGFloat(n - 1) * 14 <= width } ?? 1
    }
    let library: Library

    var body: some View {
        // Centered above the floating assistant, and scrolled when a small window cannot hold it all: nothing stays
        // under the conversation, and while it is open the input shows, right above it.
        GeometryReader { window in
            ScrollViewReader { scroller in
                ScrollView { page(window.size.width).frame(minHeight: max(0, window.size.height - model.floating), alignment: model.drawer ? .top : .center) }
                    .contentMargins(.bottom, model.floating, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: window.size.height - model.floating, initial: true) {
                        if model.drawer { scroller.scrollTo(BlankView.input, anchor: .bottom) }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.building { Button("Skip for now") { library.select(Library.gallery) }.buttonStyle(.link).padding(24) }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func page(_ width: CGFloat) -> some View {
        VStack(spacing: 18) {
            Text("What do you want to make?").font(.system(size: 28, weight: .semibold))
            if model.noAgent {
                NoAgent(model: model).frame(maxWidth: 620)
            } else {
                Text("\(model.name) builds it with you, in \(Words.path(model.places.spaces.path, home: model.places.home.path)).")
                    .foregroundStyle(.secondary)
                VStack(spacing: 18) {
                    Composer(model: model, big: true).frame(maxWidth: 620).padding(.horizontal, 24)
                    if model.building {
                        Text("It opens here when it is ready. You will be asked what it may do.").foregroundStyle(.secondary)
                    }
                }
                .id(BlankView.input)
                if !model.building {
                    HStack(spacing: 8) {
                        ForEach(BlankView.chips, id: \.0) { chip in
                            Button { model.send(chip.1) } label: {
                                Label(chip.0, systemImage: "sparkle")
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.quaternary.opacity(0.6), in: Capsule())
                                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.kind == nil)
                            .help(chip.1)
                        }
                    }
                    .font(.system(size: 12.5))
                }
            }
            if !model.building, !library.templates.isEmpty {
                Text("Or start from a template").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 22)
                // One row when the window is wide enough, else rows of three, two or one: always full rows.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(148), spacing: 14, alignment: .top), count: BlankView.columns(width - 48)), spacing: 14) {
                    ForEach(library.templates) { template in
                        VStack(spacing: 6) {
                            Preview(template: template, use: library.use)
                            Text(template.title).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        // Up, out of the way of the conversation, once it is open.
        .padding(model.drawer ? .top : .bottom, 40)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }
}
