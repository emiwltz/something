// Checks something runs from the command line, then quits. Typing the command is the consent:
//   --self-test                     the window is on screen, ⌘V pastes in the page, the page answers, its memory works,
//                                   the network is closed
//   --try claude|codex|opencode|pi --in <folder>  launch that agent there and send one message
//       --ask <text>                the message (default: a one-word reply)
//       --answer once|deny          answer its permission requests without a window
//       --force-ask                 Codex, OpenCode: ask before every command or edit, whatever the configuration
//       --model <model>             OpenCode, pi: use this model for the conversation
//       --click <button title>      or show the windows and click that button from inside something
import AppKit
import SomethingCore
import WebKit

extension Shell {
    var checking: Bool { arguments.contains("--self-test") || Shell.option("--try") != nil }
    var scriptedAnswer: PermissionAnswer? { ["once": .once, "deny": .deny][Shell.option("--answer") ?? ""] }

    func startChecks() {
        if let harness = Shell.option("--try") {
            guard let folder = Shell.option("--in") else { fail("--try needs a folder: --in <folder>.") }
            let session: AgentProcess
            do {
                session = try start(harness, in: URL(fileURLWithPath: folder), forceAsk: arguments.contains("--force-ask"),
                                    model: Shell.option("--model"))
            } catch {
                fail((error as? BridgeError)?.message ?? "\(error)")
            }
            do { try session.send(Shell.option("--ask") ?? "Reply with the single word: ready.") } catch { fail("\(error)") }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard arguments.contains("--self-test") else { return }
        // Give the window a moment to reach the screen, then report what is really there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.checkPaste() }
    }

    /// Presses ⌘V as a keyboard would, through the menu, into the page's first text field, and reads what
    /// arrived. The person's clipboard is put back as it was.
    func checkPaste() {
        let board = NSPasteboard.general
        let saved: [NSPasteboardItem] = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let sample = "first line\nsecond line"
        board.clearContents()
        board.setString(sample, forType: .string)
        window.makeFirstResponder(web)
        web.evaluateJavaScript("""
            const field = document.querySelector('textarea, input[type=text]');
            field?.closest('[hidden]')?.removeAttribute('hidden');
            field?.focus();
            """) { _, _ in
            let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                         windowNumber: self.window.windowNumber, context: nil, characters: "v",
                                         charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
            _ = NSApp.mainMenu?.performKeyEquivalent(with: press)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.web.evaluateJavaScript("document.querySelector('textarea, input[type=text]')?.value ?? null") { value, _ in
                    board.clearContents()
                    board.writeObjects(saved)
                    self.pasted = (value as? String) == sample
                    self.report()
                }
            }
        }
    }

    func report() {
        let script = """
            const state = await something.state();
            await something.store.set("self-test", 1);
            const kept = await something.store.get("self-test");
            await something.store.set("self-test", null);
            let network = "blocked";
            try { await fetch("https://example.com/", { mode: "no-cors" }); network = "reached" } catch (e) {}
            return JSON.stringify({ agents: state.agents.length, kept: kept, network: network });
            """
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            let onScreen = self.window.occlusionState.contains(.visible)
            let answer = (try? result.get()) as? String
            print("window visible: \(self.window.isVisible), on screen: \(onScreen)")
            print("menu bar icon: \(self.statusItem.button?.image != nil)")
            print("paste with ⌘V: \(self.pasted ? "two lines arrived" : "nothing arrived")")
            print("page \(self.page): \(answer ?? "no answer")")
            let good = self.window.isVisible && self.pasted && answer?.contains("\"kept\":1") == true
                && answer?.contains("\"network\":\"blocked\"") == true
            exit(good ? 0 : 1)
        }
    }

    /// In --try, quits once the agent's turn is over and says what came back.
    func checkTurn(of session: AgentProcess, _ agent: Agent) {
        guard Shell.option("--try") != nil,
              agent.status == "idle" && (agent.messages.count > 1 || agent.error != nil || !asked.isEmpty)
                || agent.status == "stopped" else { return }
        print("model: \(agent.model ?? "null"), mode: \(agent.mode ?? "null"), status: \(agent.status ?? "null")")
        print("messages: \(agent.messages.count), last from: \(agent.messages.last?.from ?? "none")")
        print("error: \(agent.error ?? "null")")
        session.stop()
        // A refused request may end the turn without a word from the agent (OpenCode does).
        exit(agent.error == nil && (agent.messages.last?.from == "agent" || !asked.isEmpty) ? 0 : 1)
    }
}
