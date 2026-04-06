import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vault: VaultViewModel
    @EnvironmentObject var settings: SettingsViewModel

    private var theme: FlapsyTheme {
        settings.isDarkMode ? .dark : .light
    }

    var body: some View {
        ZStack {
            theme.dropBg.ignoresSafeArea()

            switch vault.currentScreen {
            case .setup:
                OnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .lock:
                LockScreenView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .vault:
                VaultContainerView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Secret Key overlay (shown after vault creation or v1→v2 migration)
            if vault.showSecretKey {
                SecretKeyOverlay()
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 320, maxWidth: 420, minHeight: 480, maxHeight: 650)
        .environment(\.theme, theme)
        .font(.system(.body, design: .monospaced))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vault.currentScreen)
    }
}

/// Container for all vault panels (list, add, generator, tags, settings)
struct VaultContainerView: View {
    @EnvironmentObject var vault: VaultViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top bar (hidden when expanded note is active)
                if !vault.showExpandedNote {
                    topBar
                }
                // Panel content
                panelContent
            }

            // Import preview overlay
            if vault.showImportPreview {
                overlaySheet {
                    ImportPreviewView()
                }
            }

            // Export overlay
            if vault.showExportSheet {
                overlaySheet {
                    ExportView()
                }
            }

        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: vault.currentPanel) { _ in
            vault.showExpandedNote = false
        }
    }

    private func overlaySheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            theme.dropBg
                .ignoresSafeArea()
            ScrollView {
                content()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vault.showImportPreview)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vault.showExportSheet)
    }

    private var topBar: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 380
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.text)
                    if vault.currentPanel != .list {
                        Text(panelTitle)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.text)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if vault.currentPanel != .list {
                        Button(action: { vault.navigateToPanel(.list) }) {
                            HStack(spacing: 4) {
                                Text("\u{2190}")
                                    .font(.system(size: 11))
                                if !compact {
                                    Text("Back")
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, compact ? 8 : 12)
                            .padding(.vertical, 5)
                            .background(theme.fieldBg)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        if vault.currentPanel == .pomodoro {
                            Button(action: {
                                let pt = PomodoroTimer.shared
                                pt.stopAll()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    pt.showBlockMode.toggle()
                                }
                            }) {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.accentBlue)
                                    .padding(.horizontal, compact ? 8 : 12)
                                    .padding(.vertical, 5)
                                    .background(theme.accentBlue.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .help(PomodoroTimer.shared.showBlockMode ? "Switch to Classic" : "Switch to Block Mode")
                        }
                    } else {
                        Button(action: {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                settings.isWindowPinned.toggle()
                            }
                        }) {
                            Image(systemName: settings.isWindowPinned ? "pin.fill" : "pin.slash")
                                .font(.system(size: 11))
                                .foregroundColor(settings.isWindowPinned ? theme.accentYellow : theme.textSecondary)
                                .padding(.horizontal, compact ? 8 : 12)
                                .padding(.vertical, 5)
                                .background(settings.isWindowPinned ? theme.accentYellow.opacity(0.1) : theme.fieldBg)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(settings.isWindowPinned ? "Unpin window" : "Pin window")

                        Button(action: { vault.navigateToPanel(.addNew) }) {
                            Text("+")
                                .font(.system(size: 11))
                            .foregroundColor(theme.accentBlueLt)
                            .padding(.horizontal, compact ? 8 : 12)
                            .padding(.vertical, 5)
                            .background(theme.accentBlue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.navigateToPanel(.generator) }) {
                            Text("\u{26A1}")
                                .font(.system(size: 11))
                                .foregroundColor(theme.accentPurple)
                                .padding(.horizontal, compact ? 8 : 12)
                                .padding(.vertical, 5)
                                .background(theme.accentPurple.opacity(0.08))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.navigateToPanel(.health) }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 12))
                                    .foregroundColor(vault.flaggedItemIDs.isEmpty ? theme.accentGreen : theme.accentYellow)
                                    .padding(.horizontal, compact ? 8 : 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        (vault.flaggedItemIDs.isEmpty ? theme.accentGreen : theme.accentYellow).opacity(0.08)
                                    )
                                    .cornerRadius(6)

                                if !vault.flaggedItemIDs.isEmpty {
                                    Text("\(vault.flaggedItemIDs.count)")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(theme.accentRed)
                                        .cornerRadius(4)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.navigateToPanel(.pomodoro) }) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(theme.accentBlue)
                                .padding(.horizontal, compact ? 8 : 12)
                                .padding(.vertical, 5)
                                .background(theme.accentBlue.opacity(0.08))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.navigateToPanel(.settings) }) {
                            Text("\u{2699}")
                                .font(.system(size: 16))
                                .foregroundColor(theme.textSecondary)
                                .frame(height: 14)
                                .padding(.horizontal, compact ? 8 : 12)
                                .padding(.vertical, 5)
                                .background(theme.fieldBg)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.lock() }) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            .foregroundColor(theme.accentRed)
                            .padding(.horizontal, compact ? 8 : 12)
                            .padding(.vertical, 5)
                            .background(theme.fieldBg)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 30)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch vault.currentPanel {
        case .list:
            VaultListView()
        case .addNew:
            AddItemView()
        case .generator:
            GeneratorView()
        case .tags:
            CategoryManagerView()
        case .settings:
            SettingsView()
        case .health:
            VaultHealthView()
        case .pomodoro:
            PomodoroView()
        case .trash:
            TrashView()
        }
    }

    private var panelTitle: String {
        switch vault.currentPanel {
        case .list: return "Vault"
        case .addNew: return "New Item"
        case .generator: return "Generator"
        case .tags: return "Categories"
        case .settings: return "Settings"
        case .health: return "Health"
        case .pomodoro: return "Pomodoro"
        case .trash: return "Trash"
        }
    }
}
