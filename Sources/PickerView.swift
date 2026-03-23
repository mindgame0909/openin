import SwiftUI
import AppKit

// MARK: - ViewModel

class PickerViewModel: ObservableObject {
    @Published var selectedIndex: Int = 0
    @Published var rememberChoice: Bool = false
    let entries: [BrowserEntry]

    init(entries: [BrowserEntry]) {
        self.entries = entries
    }
}

// MARK: - Root picker view

struct PickerView: View {
    let url: URL
    let sourceApp: NSRunningApplication?
    @ObservedObject var viewModel: PickerViewModel
    let onSelect: (BrowserEntry, _ remember: Bool, _ incognito: Bool) -> Void
    let onCancel: () -> Void

    @State private var urlCopied = false

    private var urlLabel: String {
        guard let host = url.host else { return url.absoluteString }
        let full = host + url.path + (url.query.map { "?\($0)" } ?? "")
        return full.count > 58 ? String(full.prefix(58)) + "…" : full
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 5) {
                // Source app row
                if let app = sourceApp {
                    HStack(spacing: 5) {
                        if let icon = app.icon {
                            Image(nsImage: scaledIcon(icon, to: 14))
                                .resizable().frame(width: 14, height: 14)
                        }
                        Text(app.localizedName ?? "App")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("Open with…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Open with…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                // URL + copy button
                HStack(alignment: .center, spacing: 6) {
                    Text(urlLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: copyURL) {
                        Image(systemName: urlCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(urlCopied
                                             ? .green
                                             : Color(NSColor.tertiaryLabelColor))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                    .animation(.easeInOut(duration: 0.2), value: urlCopied)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 8)

            // ── Browser list ────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { idx, entry in
                        BrowserRowView(
                            entry: entry,
                            shortcutNumber: idx + 1,
                            isSelected: viewModel.selectedIndex == idx,
                            isLastUsed: idx == 0 && viewModel.entries.count > 1,
                            onSelect: { incognito in
                                onSelect(entry, viewModel.rememberChoice, incognito)
                            }
                        )
                        .onHover { if $0 { viewModel.selectedIndex = idx } }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: CGFloat(min(viewModel.entries.count, 8)) * 50)

            Divider().padding(.horizontal, 8)

            // ── Footer ──────────────────────────────────────────────
            VStack(spacing: 5) {
                // Remember choice
                if let appName = sourceApp?.localizedName {
                    Toggle(isOn: $viewModel.rememberChoice) {
                        Text("Always open **\(appName)** links in selected browser")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                }

                // Keyboard hints
                HStack {
                    Spacer()
                    Text("1–\(min(viewModel.entries.count, 9))  ⇧+N private  ↑↓  ↩  ⎋")
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Spacer()
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 410)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        urlCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { urlCopied = false }
    }

    private func scaledIcon(_ icon: NSImage, to size: CGFloat) -> NSImage {
        let copy = icon.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}

// MARK: - Browser row

struct BrowserRowView: View {
    let entry: BrowserEntry
    let shortcutNumber: Int
    let isSelected: Bool
    let isLastUsed: Bool
    let onSelect: (_ incognito: Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        // Outer button = normal open. Inner "Private" button = incognito open.
        // SwiftUI gives the inner button priority when tapped within its bounds.
        Button(action: { onSelect(false) }) {
            HStack(spacing: 10) {
                Image(nsImage: entry.browser.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        if isLastUsed {
                            Text("last used")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.quaternaryLabelColor))
                                .cornerRadius(4)
                        }
                    }
                    if let sub = entry.subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Private button — appears on hover
                if isHovered {
                    Button(action: { onSelect(true) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Private")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(NSColor.tertiaryLabelColor).opacity(0.25))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open in private / incognito  (⇧\(shortcutNumber))")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // Keyboard number badge
                if shortcutNumber <= 9 {
                    Text("\(shortcutNumber)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color(NSColor.quaternaryLabelColor))
                        .cornerRadius(5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrowserRowStyle(isSelected: isSelected))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct BrowserRowStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Color(NSColor.selectedContentBackgroundColor).opacity(0.18)
                          : Color.clear)
            )
    }
}

// MARK: - NSVisualEffectView bridge

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
