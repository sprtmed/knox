import SwiftUI

struct VaultListView: View {
    @EnvironmentObject var vault: VaultViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var updateCheck: UpdateCheckService
    @Environment(\.theme) var theme

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if vault.showExpandedNote {
                // Expanded note takes over the full space
                ItemDetailView()
            } else {
                searchBar
                typeFilterRow
                categoryFilterRow
                itemList

                if vault.selectedItem != nil {
                    ItemDetailView()
                }

                Spacer(minLength: 0)

                footer
            }

            // Hidden Cmd+K handler
            Button("") { vault.isSearchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .onChange(of: vault.isSearchFocused) { focused in
            if focused {
                isSearchFieldFocused = true
                vault.isSearchFocused = false
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(theme.textFaint)
                .padding(.leading, 10)

            ZStack(alignment: .leading) {
                if vault.searchText.isEmpty {
                    Text("Search vault\u{2026}  \u{2318}K")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                }
                TextField("", text: $vault.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.text)
                    .focused($isSearchFieldFocused)
            }
            .padding(10)

            if !vault.searchText.isEmpty {
                Button(action: { vault.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .background(theme.inputBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.inputBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Type Filter

    private var typeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                FilterPill(title: "All", isActive: vault.typeFilter == nil) {
                    vault.typeFilter = nil
                    vault.selectedItemID = nil
                }
                FilterPill(title: "\u{1F511} Logins", isActive: vault.typeFilter == .login) {
                    vault.typeFilter = .login
                    vault.selectedItemID = nil
                }
                FilterPill(title: "\u{1F4B3} Cards", isActive: vault.typeFilter == .card) {
                    vault.typeFilter = .card
                    vault.selectedItemID = nil
                }
                FilterPill(title: "\u{1F4DD} Notes", isActive: vault.typeFilter == .note) {
                    vault.typeFilter = .note
                    vault.selectedItemID = nil
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Category Filter

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                FilterPill(title: "\u{229E} All", isActive: vault.activeCategory == "all") {
                    vault.activeCategory = "all"
                    vault.selectedItemID = nil
                }
                Button(action: {
                    vault.showFavoritesOnly.toggle()
                    if vault.showFavoritesOnly {
                        vault.activeCategory = "all"
                    }
                    vault.selectedItemID = nil
                }) {
                    Text(vault.showFavoritesOnly ? "\u{2605}" : "\u{2606}")
                        .font(.system(size: 13))
                        .foregroundColor(vault.showFavoritesOnly ? Color(hex: "fbbf24") : theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(vault.showFavoritesOnly ? theme.pillBg : Color.clear)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                ForEach(vault.categories) { cat in
                    CategoryPill(
                        label: cat.label,
                        colorHex: cat.color,
                        isActive: vault.activeCategory == cat.key
                    ) {
                        vault.activeCategory = cat.key
                        vault.selectedItemID = nil
                    }
                }
                Button(action: { vault.navigateToPanel(.tags) }) {
                    Text("\u{FF0B}")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textFaint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vault.filteredItems) { item in
                    VaultItemRow(item: item, searchQuery: vault.searchText)
                }
                if vault.filteredItems.isEmpty {
                    Text("No items found")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }
            }
        }
        .frame(maxHeight: vault.selectedItemID != nil ? 120 : .infinity)
        .layoutPriority(1)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(vault.activeItems.count) items \u{00B7} AES-256 \u{00B7} v\(updateCheck.currentVersion)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textGhost)
                Spacer()
                if !vault.trashedItems.isEmpty {
                    Button(action: { vault.navigateToPanel(.trash) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text("\(vault.trashedItems.count)")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundColor(theme.textGhost)
                    }
                    .buttonStyle(.plain)
                }
                Text("Auto-lock: \(settings.autoLockEnabled ? "\(Int(settings.autoLockMinutes))m" : "Off")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textGhost)
            }
            if updateCheck.updateAvailable, let version = updateCheck.latestVersion {
                Button(action: {
                    if let url = URL(string: "https://github.com/sprtmed/Knox-Password-Manager/releases/latest") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                        Text("v\(version) available — download update")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(theme.accentBlueLt)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.cardBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Vault Item Row

struct VaultItemRow: View {
    let item: VaultItem
    var searchQuery: String = ""
    @EnvironmentObject var vault: VaultViewModel
    @Environment(\.theme) var theme

    private var isSelected: Bool {
        vault.selectedItemID == item.id
    }

    var body: some View {
        HStack(spacing: 10) {
            itemIcon

            VStack(alignment: .leading, spacing: 2) {
                highlightedText(item.name, query: searchQuery)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                highlightedText(item.subtitle, query: searchQuery)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textFaint)
                    .lineLimit(1)
            }

            Spacer()

            if vault.compromisedItemIDs.contains(item.id) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.accentRed)
                    .help(healthTooltip)
            } else if vault.flaggedItemIDs.contains(item.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.accentYellow)
                    .help(healthTooltip)
            }

            if item.type == .login, item.password != nil && !item.password!.isEmpty {
                Button(action: { vault.copyToClipboard(item.password!, fieldName: "quickcopy-\(item.id)") }) {
                    Image(systemName: vault.copiedField == "quickcopy-\(item.id)" ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(vault.copiedField == "quickcopy-\(item.id)" ? theme.accentGreen : theme.textFaint)
                        .frame(width: 24, height: 24)
                        .background(vault.copiedField == "quickcopy-\(item.id)" ? theme.accentGreen.opacity(0.15) : theme.fieldBg)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Copy password")
            }

            Button(action: { vault.toggleFavorite(item.id) }) {
                Text(item.isFavorite ? "\u{2605}" : "\u{2606}")
                    .font(.system(size: 14))
                    .foregroundColor(item.isFavorite ? Color(hex: "fbbf24") : theme.textFaint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.lastUsedDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textFaint)

                if item.type == .login, let password = item.password {
                    let strength = PasswordStrength.calculate(password)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.fieldBg)
                            .frame(width: 36, height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PasswordStrength.color(for: strength))
                            .frame(width: 36 * CGFloat(strength) / 100, height: 3)
                    }
                    .frame(width: 36, height: 3)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
        .background(isSelected ? theme.activeBg : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? theme.accentBlue : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                vault.selectedItemID = isSelected ? nil : item.id
                vault.showPassword = false
                vault.showCardNumber = false
                vault.showCVV = false
                vault.isEditingItem = false
            }
        }
    }

    private var healthTooltip: String {
        var issues: [String] = []
        if vault.compromisedItemIDs.contains(item.id) { issues.append("Breached password") }
        if vault.weakPasswordItemIDs.contains(item.id) { issues.append("Weak password") }
        if vault.reusedPasswordItemIDs.contains(item.id) { issues.append("Reused password") }
        if vault.duplicateLoginItemIDs.contains(item.id) { issues.append("Duplicate login") }
        return issues.joined(separator: ", ")
    }

    private var itemIcon: some View {
        let catColor = vault.categoryFor(key: item.category)?.color ?? "8b5cf6"
        let colors = theme.categoryColors(hex: catColor)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.background)
                .frame(width: 36, height: 36)
            Group {
                switch item.type {
                case .card:
                    Text("\u{1F4B3}")
                        .font(.system(size: 16))
                case .note:
                    Text("\u{1F4DD}")
                        .font(.system(size: 16))
                case .login:
                    Circle()
                        .fill(colors.foreground)
                        .frame(width: 12, height: 12)
                }
            }
        }
    }

    // MARK: - Fuzzy Highlight

    private func highlightedText(_ fullText: String, query: String) -> Text {
        guard !query.isEmpty,
              let match = FuzzySearch.match(query: query, in: fullText) else {
            return Text(fullText)
        }

        let chars = Array(fullText)
        let matchedSet = Set(match.matchedIndices)
        var result = Text("")

        for (i, char) in chars.enumerated() {
            let charText = Text(String(char))
            if matchedSet.contains(i) {
                result = result + charText.foregroundColor(theme.accentBlueLt).bold()
            } else {
                result = result + charText
            }
        }
        return result
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? theme.accentBlueLt : theme.textMuted)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? theme.pillBg : Color.clear)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Pill (with color dot)

struct CategoryPill: View {
    let label: String
    let colorHex: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? theme.accentBlueLt : theme.textMuted)
            }
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isActive ? theme.pillBg : Color.clear)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}
