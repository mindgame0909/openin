import AppKit
import SwiftUI

private class PickerPanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }

    // Swallow ALL key events at the window level so nothing can leak up to NSApp → NSBeep.
    // The local monitor in PickerWindowController does the actual key handling.
    override func keyDown(with event: NSEvent) { /* intentionally silent */ }

    // Escape on a panel can trigger cancelOperation → system sound. Prevent it.
    override func cancelOperation(_ sender: Any?) { /* intentionally silent */ }
}

class PickerWindowController: NSWindowController {
    private let viewModel: PickerViewModel
    private let onSelect: (BrowserEntry, Bool, Bool) -> Void   // entry, remember, incognito
    private let onCancel: () -> Void
    private var keyMonitor: Any?

    init(
        url: URL,
        entries: [BrowserEntry],
        sourceApp: NSRunningApplication?,
        onSelect: @escaping (BrowserEntry, _ remember: Bool, _ incognito: Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = PickerViewModel(entries: entries)
        self.onSelect  = onSelect
        self.onCancel  = onCancel

        // NOTE: No .nonactivatingPanel — that was silently preventing the panel from
        // becoming the key window, so arrow/Esc events were going to the other app
        // (WhatsApp, Slack…) which had no handler → NSBeep.
        let panel = PickerPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        super.init(window: panel)

        let vm   = viewModel
        let view = PickerView(
            url: url,
            sourceApp: sourceApp,
            viewModel: vm,
            onSelect: { [weak self] entry, remember, incognito in
                self?.onSelect(entry, remember, incognito)
            },
            onCancel: { [weak self] in self?.onCancel() }
        )

        let hosting     = NSHostingController(rootView: view)
        let fittingSize = hosting.sizeThatFits(in: NSSize(width: 410, height: 10_000))
        panel.setContentSize(fittingSize)
        panel.contentView = hosting.view

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x  = sf.midX - fittingSize.width / 2
            let y  = sf.maxY - fittingSize.height - 140
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        startKeyMonitoring()
    }

    override func close() {
        stopKeyMonitoring()
        super.close()
    }

    // MARK: - Keyboard

    private func startKeyMonitoring() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func stopKeyMonitoring() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let entries   = viewModel.entries
        let incognito = event.modifierFlags.contains(.shift)   // ⇧ = open private

        switch event.keyCode {
        case 53:        // Escape
            onCancel()
            return nil

        case 36, 76:    // Return / Enter  (⇧↩ = incognito)
            if viewModel.selectedIndex < entries.count {
                onSelect(entries[viewModel.selectedIndex],
                         viewModel.rememberChoice,
                         incognito)
            }
            return nil

        case 125:       // ↓
            viewModel.selectedIndex = min(viewModel.selectedIndex + 1, entries.count - 1)
            return nil

        case 126:       // ↑
            viewModel.selectedIndex = max(viewModel.selectedIndex - 1, 0)
            return nil

        default:
            // 1–9: open  |  ⇧1–9: open incognito
            if let ch = event.charactersIgnoringModifiers,
               let n = Int(ch), n >= 1 && n <= 9 {
                let idx = n - 1
                if idx < entries.count {
                    onSelect(entries[idx], viewModel.rememberChoice, incognito)
                }
                return nil
            }
        }
        return event
    }
}
