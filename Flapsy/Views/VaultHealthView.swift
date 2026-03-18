import SwiftUI

    enum HealthFilter: String, CaseIterable {
        case all = "All"
        case compromised = "Breached"
        case reused = "Reused"
        case weak = "Weak"
        case duplicates = "Duplicates"
    }

struct VaultHealthView: View {
    @EnvironmentObject var vault: VaultViewModel
    @Environment(\.theme) var theme
    @State private var filter: HealthFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            if vault.showExpandedNote {
                ItemDetailView()
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    healthScoreCard

                    if !vault.flaggedItemIDs.isEmpty {
                        filterBar
                    }

                    // Breach check status / results
                    if vault.isCheckingBreaches {
                        breachCheckingCard
                    }

                    if showSection(.compromised) && !vault.compromisedItemIDs.isEmpty {
                        compromisedSection
                    }

                    if showSection(.reused) && !vault.reusedPasswordGroups.isEmpty {
                        issueSection(
                            title: "REUSED PASSWORDS",
                            icon: "arrow.triangle.2.circlepath",
                            color: theme.accentRed,
                            groups: vault.reusedPasswordGroups,
                            groupLabel: { items in
                                "\(items.count) items share the same password"
                            }
                        )
                    }

                    if showSection(.weak) && !vault.weakPasswordItemIDs.isEmpty {
                        weakPasswordsSection
                    }

                    if showSection(.duplicates) && !vault.duplicateLoginGroups.isEmpty {
                        issueSection(
                            title: "DUPLICATE LOGINS",
                            icon: "doc.on.doc.fill",
                            color: theme.accentYellow,
                            groups: vault.duplicateLoginGroups,
                            groupLabel: { items in
                                let url = items.first?.url ?? "Unknown"
                                let user = items.first?.username ?? ""
                                return "\(url) (\(user))"
                            }
                        )
                    }

                    if vault.flaggedItemIDs.isEmpty {
                        allClearCard
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: vault.selectedItemID != nil ? 200 : .infinity)

            if vault.selectedItem != nil {
                ItemDetailView()
            }

            Spacer(minLength: 0)
            } // else (not expanded)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectItem(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            vault.selectedItemID = vault.selectedItemID == id ? nil : id
            vault.showPassword = false
            vault.showCardNumber = false
            vault.showCVV = false
            vault.isEditingItem = false
        }
    }

    private func showSection(_ section: HealthFilter) -> Bool {
        filter == .all || filter == section
    }

    // MARK: - Health Score Card

    private var healthScoreCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(theme.fieldBg, lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(vault.healthScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: vault.healthScore)

                VStack(spacing: 2) {
                    Text("\(vault.healthScore)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(scoreColor)
                    Text("%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                }
            }

            Text(scoreLabel)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(scoreColor)

            let loginCount = vault.activeItems.filter { $0.type == .login }.count
            Text("\(loginCount) login\(loginCount == 1 ? "" : "s") analyzed")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textFaint)

            if !vault.compromisedItemIDs.isEmpty {
                Text("\(vault.compromisedItemIDs.count) compromised")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.accentRed)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(theme.cardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.cardBorder, lineWidth: 1)
        )
    }

    private var scoreColor: Color {
        if vault.healthScore >= 90 { return theme.accentGreen }
        if vault.healthScore >= 70 { return theme.accentYellow }
        return theme.accentRed
    }

    private var scoreLabel: String {
        if vault.healthScore >= 90 { return "Excellent" }
        if vault.healthScore >= 70 { return "Good" }
        if vault.healthScore >= 50 { return "Fair" }
        return "Needs Attention"
    }

    // MARK: - Filter Bar

    @State private var hoveredFilter: HealthFilter? = nil

    private var filterBar: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 350
            HStack(spacing: 6) {
                ForEach(HealthFilter.allCases, id: \.self) { option in
                    let count = filterCount(for: option)
                    let isActive = filter == option
                    let isHovered = hoveredFilter == option
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { filter = option } }) {
                        HStack(spacing: 4) {
                            if option != .all {
                                Image(systemName: filterIcon(for: option))
                                    .font(.system(size: 9))
                            }
                            if !compact {
                                Text(option.rawValue)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: isHovered || isActive, vertical: false)
                            }
                            if compact {
                                if option == .all {
                                    Text(option.rawValue)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .fixedSize()
                                }
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(isActive ? filterColor(for: option) : theme.textFaint)
                                        .fixedSize()
                                }
                            } else if option != .all && count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isActive ? filterColor(for: option) : theme.textFaint)
                                    .fixedSize()
                            }
                        }
                        .foregroundColor(isActive ? filterColor(for: option) : theme.textSecondary)
                        .padding(.horizontal, compact ? 6 : 10)
                        .padding(.vertical, 5)
                        .background(isActive ? filterColor(for: option).opacity(0.12) : theme.fieldBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive ? filterColor(for: option).opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if !compact {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredFilter = hovering ? option : nil
                            }
                        }
                    }
                }
                Spacer()
            }
        }
        .frame(height: 28)
    }

    private func filterIcon(for option: HealthFilter) -> String {
        switch option {
        case .all: return ""
        case .compromised: return "exclamationmark.shield.fill"
        case .reused: return "arrow.triangle.2.circlepath"
        case .weak: return "exclamationmark.triangle.fill"
        case .duplicates: return "doc.on.doc.fill"
        }
    }

    private func filterColor(for option: HealthFilter) -> Color {
        switch option {
        case .all: return theme.accentBlueLt
        case .compromised: return theme.accentRed
        case .reused: return theme.accentRed
        case .weak: return theme.accentYellow
        case .duplicates: return theme.accentYellow
        }
    }

    private func filterCount(for option: HealthFilter) -> Int {
        switch option {
        case .all: return vault.flaggedItemIDs.count
        case .compromised: return vault.compromisedItemIDs.count
        case .reused: return vault.reusedPasswordItemIDs.count
        case .weak: return vault.weakPasswordItemIDs.count
        case .duplicates: return vault.duplicateLoginItemIDs.count
        }
    }

    // MARK: - Breach Checking Card

    private var breachCheckingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accentBlueLt)
            Text("Checking passwords against breach database\u{2026}")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.accentBlue.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.accentBlue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Compromised Passwords Section

    private var compromisedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormLabel("COMPROMISED PASSWORDS")

            let compromisedItems = vault.activeItems.filter { vault.compromisedItemIDs.contains($0.id) }
            VStack(spacing: 4) {
                ForEach(compromisedItems) { item in
                    Button(action: { selectItem(item.id) }) {
                        HStack(spacing: 8) {
                            itemIcon(for: item)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.text)
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(theme.textFaint)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let count = vault.breachOccurrences[item.id] {
                                Text("\(formatBreachCount(count))x")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(theme.accentRed)
                            }
                            Text("\u{203A}")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textGhost)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.fieldBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(theme.accentRed.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accentRed.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textGhost)
                Text("Only SHA-1 prefixes (5 chars) are sent \u{2014} full passwords never leave your device.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textGhost)
            }
        }
    }

    private func formatBreachCount(_ count: Int) -> String {
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }

    // MARK: - Reused / Duplicate Section

    private func issueSection(
        title: String,
        icon: String,
        color: Color,
        groups: [[VaultItem]],
        groupLabel: @escaping ([VaultItem]) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FormLabel(title)

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(color)
                        Text(groupLabel(group))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }

                    ForEach(group) { item in
                        Button(action: { selectItem(item.id) }) {
                            HStack(spacing: 8) {
                                itemIcon(for: item)
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(theme.text)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(theme.textFaint)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\u{203A}")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textGhost)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.fieldBg)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(theme.cardBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.cardBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Weak Passwords Section

    private var weakPasswordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormLabel("WEAK PASSWORDS")

            let weakItems = vault.activeItems.filter { vault.weakPasswordItemIDs.contains($0.id) }
            VStack(spacing: 4) {
                ForEach(weakItems) { item in
                    Button(action: { selectItem(item.id) }) {
                        HStack(spacing: 8) {
                            itemIcon(for: item)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(theme.text)
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(theme.textFaint)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let pw = item.password {
                                let s = PasswordStrength.calculate(pw)
                                Text("\(s)%")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(PasswordStrength.color(for: s))
                            }
                            Text("\u{203A}")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textGhost)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.fieldBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(theme.cardBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - All Clear

    private var allClearCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(theme.accentGreen)
            Text("All Clear")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentGreen)
            Text("No issues found in your vault")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(theme.accentGreen.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.accentGreen.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Item Icon

    private func itemIcon(for item: VaultItem) -> some View {
        let catColor = vault.categoryFor(key: item.category)?.color ?? "8b5cf6"
        let colors = theme.categoryColors(hex: catColor)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(colors.background)
            Group {
                switch item.type {
                case .card:
                    Text("\u{1F4B3}").font(.system(size: 10))
                case .note:
                    Text("\u{1F4DD}").font(.system(size: 10))
                case .login:
                    Circle()
                        .fill(Color(hex: catColor))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}
