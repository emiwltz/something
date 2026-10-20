// The blank page (plan B.4), the center when no space is open: New Space (⌘N), and where the tour ends. "What do you
// want to make?", the assistant's input made big, and three suggestions that each send a whole sentence. Without a
// coding agent, the notice takes the input's place.
import SwiftUI

struct BlankView: View {
    /// Each suggestion and the sentence it sends.
    static let chips = [
        ("Who is waiting for me", "Make me a space that shows which of my agents are waiting for me, and lets me answer the ones I can."),
        ("A morning brief of my agents", "Make me a space like a morning newspaper: what each of my agents did since yesterday."),
        ("A small game for my breaks", "Make me a small game I can play in a minute between two tasks, with my best score kept."),
    ]

    @Bindable var model: AssistantModel

    var body: some View {
        VStack(spacing: 18) {
            Text("What do you want to make?").font(.system(size: 28, weight: .semibold))
            if model.noAgent {
                NoAgent(model: model).frame(maxWidth: 620)
            } else {
                Text("\(model.name) builds it with you, in \(Words.path(model.places.spaces.path, home: model.places.home.path)).")
                    .foregroundStyle(.secondary)
                Composer(model: model, big: true).frame(width: 620)
                if model.building {
                    Text("It opens here when it is ready. You will be asked what it may do.").foregroundStyle(.secondary)
                } else {
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
        }
        // Up, out of the way of the conversation, once it is open.
        .padding(model.drawer ? .top : .bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.drawer ? .top : .center)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
