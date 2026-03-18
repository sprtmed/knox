import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject var vault: VaultViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @Environment(\.theme) var theme
    @State private var showDeleteConfirmation = false
    @State private var showMarkdownPreview = true

    private func dismissDetail() {
        withAnimation(.easeInOut(duration: 0.15)) {
            vault.selectedItemID = nil
            vault.showPassword = false
            vault.showCardNumber = false
            vault.showCVV = false
            vault.isEditingItem = false
        }
    }

    var body: some View {
        if let item = vault.selectedItem {
            if vault.isEditingItem {
                editView(item)
            } else if vault.showExpandedNote {
                readOnlyExpandedNote(item)
            } else {
                detailView(item)
            }
        }
        EmptyView()
            .onChange(of: vault.isEditingItem) { editing in
                if !editing {
                    vault.showExpandedNote = false
                    vault.expandedNoteAutoOpened = false
                }
            }
            .onChange(of: vault.selectedItemID) { newID in
                vault.showExpandedNote = false
                vault.expandedNoteAutoOpened = false
                // Auto-expand if setting is ON and item has notes
                if settings.alwaysExpandNotes, let id = newID, let item = vault.items.first(where: { $0.id == id }) {
                    let hasNotes: Bool = {
                        switch item.type {
                        case .login: return !(item.loginNotes ?? "").isEmpty
                        case .card: return !(item.cardNotes ?? "").isEmpty
                        case .note: return !(item.noteText ?? "").isEmpty
                        }
                    }()
                    if hasNotes {
                        vault.showExpandedNote = true
                    }
                }
            }
    }

    @ViewBuilder
    private func readOnlyExpandedNote(_ item: VaultItem) -> some View {
        let noteText: String = {
            switch item.type {
            case .login: return item.loginNotes ?? ""
            case .card: return item.cardNotes ?? ""
            case .note: return item.noteText ?? ""
            }
        }()
        ExpandedNoteView(
            text: .constant(noteText),
            title: item.type == .note ? "SECURE NOTE" : "NOTES",
            readOnly: true,
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vault.showExpandedNote = false
                }
            },
            onEdit: {
                vault.requestEditWithReauth(item)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail View (read-only)

    private func detailView(_ item: VaultItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    // Close button
                    Button(action: { dismissDetail() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textFaint)
                    }
                    .buttonStyle(.plain)

                    // Tappable icon + name area (click to dismiss)
                    let catColor = vault.categoryFor(key: item.category)?.color ?? "8b5cf6"
                    let colors = theme.categoryColors(hex: catColor)
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colors.background)
                                .frame(width: 28, height: 28)
                            typeIcon(for: item)
                        }
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.text)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dismissDetail() }

                    // Action buttons (not dismissable)
                    Button(action: { vault.requestEditWithReauth(item) }) {
                        Text("\u{270E}")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.fieldBg)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    Button(action: {
                        if settings.confirmBeforeDelete {
                            showDeleteConfirmation = true
                        } else {
                            vault.deleteItem(item.id)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(theme.accentRed)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.fieldBg)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    Button(action: { vault.toggleFavorite(item.id) }) {
                        Text(item.isFavorite ? "\u{2605}" : "\u{2606}")
                            .font(.system(size: 16))
                            .foregroundColor(item.isFavorite ? Color(hex: "fbbf24") : theme.textGhost)
                    }
                    .buttonStyle(.plain)
                }

                switch item.type {
                case .login:
                    loginDetail(item)
                case .card:
                    cardDetail(item)
                case .note:
                    noteDetail(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(theme.cardBorder)
                    .frame(height: 1)
                LinearGradient(
                    colors: [Color.black.opacity(0.12), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 8)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                vault.deleteItem(item.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(item.name)\"?")
        }
        .overlay {
            if vault.showReauthPrompt {
                ReauthOverlay()
            }
        }
    }

    private func expandedNoteBinding(for item: VaultItem) -> Binding<String> {
        switch item.type {
        case .login: return $vault.editLoginNotes
        case .card: return $vault.editCardNotes
        case .note: return $vault.editNoteText
        }
    }

    // MARK: - Edit View

    @ViewBuilder
    private func editView(_ item: VaultItem) -> some View {
        if vault.showExpandedNote {
            ExpandedNoteView(
                text: expandedNoteBinding(for: item),
                title: item.type == .note ? "SECURE NOTE" : "NOTES",
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vault.showExpandedNote = false
                    }
                },
                onSave: {
                    vault.saveEditedItem()
                },
                onCancel: {
                    vault.cancelEditing()
                },
                onDelete: {
                    vault.deleteItem(item.id)
                    vault.isEditingItem = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Name
                    FormLabel("NAME")
                    FormTextField(placeholder: "Item name\u{2026}", text: $vault.editName)

                    // Type-specific fields
                    switch item.type {
                    case .login:
                        loginEditFields
                    case .card:
                        cardEditFields
                    case .note:
                        noteEditFields
                    }

                    // Category picker
                    if !vault.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            FormLabel("CATEGORY")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(vault.categories) { cat in
                                        Button(action: { vault.editCategory = cat.key }) {
                                            HStack(spacing: 5) {
                                                Circle()
                                                    .fill(Color(hex: cat.color))
                                                    .frame(width: 8, height: 8)
                                                Text(cat.label)
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(vault.editCategory == cat.key ? theme.accentBlueLt : theme.textMuted)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(vault.editCategory == cat.key ? theme.pillBg : Color.clear)
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(
                                                        vault.editCategory == cat.key ? theme.accentBlue.opacity(0.27) : theme.inputBorder,
                                                        lineWidth: 1
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        Button(action: { vault.saveEditedItem() }) {
                            Text("Save")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "3b82f6"), Color(hex: "2563eb")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: { vault.cancelEditing() }) {
                            Text("Cancel")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(theme.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(theme.fieldBg)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: {
                            vault.deleteItem(item.id)
                            vault.isEditingItem = false
                        }) {
                            Text("\u{2715} Delete")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(theme.accentRed)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(theme.fieldBg)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(theme.cardBorder)
                        .frame(height: 1)
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Login Edit Fields

    @ViewBuilder
    private var loginEditFields: some View {
        FormLabel("URL")
        FormTextField(placeholder: "https://\u{2026}", text: $vault.editUrl)
        FormLabel("USERNAME")
        FormTextField(placeholder: "Username\u{2026}", text: $vault.editUsername)
        FormLabel("PASSWORD")
        HStack(spacing: 6) {
            ZStack(alignment: .trailing) {
                if vault.showEditPassword {
                    FormTextField(placeholder: "Enter or generate\u{2026}", text: $vault.editPassword)
                } else {
                    ZStack(alignment: .leading) {
                        if vault.editPassword.isEmpty {
                            Text("Enter or generate\u{2026}")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(theme.textSecondary)
                                .padding(10)
                        }
                        SecureField("", text: $vault.editPassword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(theme.text)
                            .padding(10)
                    }
                    .background(theme.inputBg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.inputBorder, lineWidth: 1)
                    )
                }
                Button(action: { vault.showEditPassword.toggle() }) {
                    Text(vault.showEditPassword ? "Hide" : "Show")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }

            Button(action: {
                vault.editPassword = GeneratorViewModel.secureRandomPassword()
            }) {
                Text("\u{26A1} Gen")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.accentPurple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.accentPurple.opacity(0.08))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        FormLabel("2FA SECRET (OPTIONAL)")
        FormTextField(placeholder: "Paste base32 key or otpauth:// URI", text: $vault.editTotpSecret)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FormLabel("NOTES (OPTIONAL)")
                Spacer()
                NoteExpandButton {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vault.showExpandedNote = true
                    }
                }
            }
            TextEditor(text: $vault.editLoginNotes)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 50)
                .background(theme.inputBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
        }
        .onAppear {
            if settings.alwaysExpandNotes && !vault.expandedNoteAutoOpened {
                vault.expandedNoteAutoOpened = true
                vault.showExpandedNote = true
            }
        }
    }

    // MARK: - Card Edit Fields

    @ViewBuilder
    private var cardEditFields: some View {
        HStack {
            Text("Card Type")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.text)
            Spacer()
            FlapsyDropdown(
                value: vault.editCardType.isEmpty ? "Select type" : vault.editCardType,
                options: VaultItem.cardTypes,
                onChange: { vault.editCardType = $0 },
                width: 190
            )
        }
        .padding(.vertical, 4)
        .zIndex(10)
        FormLabel("CARDHOLDER")
        FormTextField(placeholder: "Name on card\u{2026}", text: $vault.editCardHolder)
        FormLabel("CARD NUMBER")
        FormTextField(placeholder: "0000 0000 0000 0000", text: $vault.editCardNumber)
            .onChange(of: vault.editCardNumber) { val in
                let formatted = VaultViewModel.formatCardNumber(val)
                if formatted != val { vault.editCardNumber = formatted }
            }
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                FormLabel("EXPIRY")
                FormTextField(placeholder: "MM/YY", text: $vault.editExpiry)
                    .onChange(of: vault.editExpiry) { val in
                        let formatted = VaultViewModel.formatExpiry(val)
                        if formatted != val { vault.editExpiry = formatted }
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                FormLabel("CVV")
                FormTextField(placeholder: "\u{2022}\u{2022}\u{2022}", text: $vault.editCvv)
                    .onChange(of: vault.editCvv) { val in
                        let formatted = VaultViewModel.formatCVV(val)
                        if formatted != val { vault.editCvv = formatted }
                    }
            }
        }
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FormLabel("NOTES (OPTIONAL)")
                Spacer()
                NoteExpandButton {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vault.showExpandedNote = true
                    }
                }
            }
            TextEditor(text: $vault.editCardNotes)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 50)
                .background(theme.inputBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
        }
        .onAppear {
            if settings.alwaysExpandNotes && !vault.expandedNoteAutoOpened {
                vault.expandedNoteAutoOpened = true
                vault.showExpandedNote = true
            }
        }
    }

    // MARK: - Note Edit Fields

    @ViewBuilder
    private var noteEditFields: some View {
        HStack {
            FormLabel("SECURE NOTE")
            Spacer()
            NoteExpandButton {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vault.showExpandedNote = true
                }
            }
        }
        TextEditor(text: $vault.editNoteText)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(theme.text)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: 80)
            .background(theme.inputBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.inputBorder, lineWidth: 1)
            )
            .onAppear {
                if settings.alwaysExpandNotes && !vault.expandedNoteAutoOpened {
                    vault.expandedNoteAutoOpened = true
                    vault.showExpandedNote = true
                }
            }
    }

    // MARK: - Type Icon

    @ViewBuilder
    private func typeIcon(for item: VaultItem) -> some View {
        switch item.type {
        case .card:
            Text("\u{1F4B3}").font(.system(size: 13))
        case .note:
            Text("\u{1F4DD}").font(.system(size: 13))
        case .login:
            let catColor = vault.categoryFor(key: item.category)?.color ?? "8b5cf6"
            Circle()
                .fill(Color(hex: catColor))
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Login Detail

    @ViewBuilder
    private func loginDetail(_ item: VaultItem) -> some View {
        if let url = item.url, !url.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .tracking(1)
                    Text(url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.accentBlueLt)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .onTapGesture {
                            let urlString = url.hasPrefix("http://") || url.hasPrefix("https://") ? url : "https://\(url)"
                            if let openURL = URL(string: urlString) {
                                NSWorkspace.shared.open(openURL)
                            }
                        }
                }
                Spacer()
                HStack(spacing: 4) {
                    if settings.openURLCopyPassword,
                       let password = item.password, !password.isEmpty {
                        IconButton(
                            icon: vault.copiedField == "pass" ? "checkmark" : "arrow.up.forward.app",
                            isActive: vault.copiedField == "pass",
                            action: {
                                vault.copyToClipboard(password, fieldName: "pass")
                                let urlString = url.hasPrefix("http://") || url.hasPrefix("https://") ? url : "https://\(url)"
                                if let openURL = URL(string: urlString) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        NSWorkspace.shared.open(openURL)
                                    }
                                }
                            }
                        )
                    }
                    IconButton(
                        icon: vault.copiedField == "url" ? "checkmark" : "doc.on.doc",
                        isActive: vault.copiedField == "url",
                        action: { vault.copyToClipboard(url, fieldName: "url") }
                    )
                }
            }
            .padding(12)
            .background(theme.fieldBg)
            .cornerRadius(8)
        }

        if let username = item.username {
            DetailFieldRow(
                label: "USERNAME",
                value: username,
                copyAction: { vault.copyToClipboard(username, fieldName: "user") },
                isCopied: vault.copiedField == "user"
            )
        }

        if let password = item.password {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PASSWORD")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .tracking(1)
                    Text(vault.showPassword ? password : String(repeating: "\u{2022}", count: 14))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(vault.showPassword ? theme.text : theme.accentBlueLt)
                }
                Spacer()
                HStack(spacing: 4) {
                    IconButton(
                        icon: vault.showPassword ? "eye.slash" : "eye",
                        isActive: false,
                        action: { vault.showPassword.toggle() }
                    )
                    IconButton(
                        icon: vault.copiedField == "pass" ? "checkmark" : "doc.on.doc",
                        isActive: vault.copiedField == "pass",
                        action: { vault.copyToClipboard(password, fieldName: "pass") }
                    )
                }
            }
            .padding(12)
            .background(theme.fieldBg)
            .cornerRadius(8)

        if let totp = item.totpSecret, !totp.isEmpty {
            TOTPDisplayRow(secret: totp)
        }

            // Strength bar
            let strength = PasswordStrength.calculate(password)
            HStack(spacing: 10) {
                Text("STRENGTH")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textFaint)
                    .tracking(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.fieldBg)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PasswordStrength.color(for: strength))
                            .frame(width: geo.size.width * CGFloat(strength) / 100)
                    }
                }
                .frame(height: 4)
                Text("\(strength)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(PasswordStrength.color(for: strength))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Password history
            if let history = item.previousPasswords, !history.isEmpty {
                PasswordHistorySection(history: history)
            }
        }

        if let notes = item.loginNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .tracking(1)
                    Spacer()
                    NoteExpandButton {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vault.showExpandedNote = true
                        }
                    }
                }
                Text(notes)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.fieldBg)
            .cornerRadius(8)
        }
    }

    // MARK: - Card Detail

    @ViewBuilder
    private func cardDetail(_ item: VaultItem) -> some View {
        if let cardType = item.cardType, !cardType.isEmpty {
            HStack(spacing: 6) {
                Text(cardType)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.accentBlueLt)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.accentBlue.opacity(0.1))
                    .cornerRadius(6)
                Spacer()
            }
        }

        if let holder = item.cardHolder {
            DetailFieldRow(
                label: "CARDHOLDER",
                value: holder,
                copyAction: { vault.copyToClipboard(holder, fieldName: "holder") },
                isCopied: vault.copiedField == "holder"
            )
        }

        if let number = item.cardNumber {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARD NUMBER")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .tracking(1)
                    Text(vault.showCardNumber ? number : "\u{2022}\u{2022}\u{2022}\u{2022} \u{2022}\u{2022}\u{2022}\u{2022} \u{2022}\u{2022}\u{2022}\u{2022} \(String(number.suffix(4)))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(vault.showCardNumber ? theme.text : theme.accentBlueLt)
                        .tracking(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    IconButton(
                        icon: vault.showCardNumber ? "eye.slash" : "eye",
                        isActive: false,
                        action: { vault.showCardNumber.toggle() }
                    )
                    IconButton(
                        icon: vault.copiedField == "cardnum" ? "checkmark" : "doc.on.doc",
                        isActive: vault.copiedField == "cardnum",
                        action: { vault.copyToClipboard(number, fieldName: "cardnum") }
                    )
                }
            }
            .padding(12)
            .background(theme.fieldBg)
            .cornerRadius(8)
        }

        HStack(spacing: 6) {
            if let expiry = item.expiry {
                DetailFieldRow(
                    label: "EXPIRY",
                    value: expiry,
                    copyAction: { vault.copyToClipboard(expiry, fieldName: "exp") },
                    isCopied: vault.copiedField == "exp"
                )
            }
            if let cvv = item.cvv {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CVV")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(theme.textFaint)
                            .tracking(1)
                        Text(vault.showCVV ? cvv : "\u{2022}\u{2022}\u{2022}")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(vault.showCVV ? theme.text : theme.accentBlueLt)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        IconButton(
                            icon: vault.showCVV ? "eye.slash" : "eye",
                            isActive: false,
                            action: { vault.showCVV.toggle() }
                        )
                        IconButton(
                            icon: vault.copiedField == "cvv" ? "checkmark" : "doc.on.doc",
                            isActive: vault.copiedField == "cvv",
                            action: { vault.copyToClipboard(cvv, fieldName: "cvv") }
                        )
                    }
                }
                .padding(12)
                .background(theme.fieldBg)
                .cornerRadius(8)
            }
        }

        if let notes = item.cardNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textFaint)
                        .tracking(1)
                    Spacer()
                    NoteExpandButton {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vault.showExpandedNote = true
                        }
                    }
                }
                Text(notes)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.fieldBg)
            .cornerRadius(8)
        }
    }

    // MARK: - Note Detail

    @ViewBuilder
    private func noteDetail(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SECURE NOTE")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textFaint)
                    .tracking(1)
                Spacer()
                NoteExpandButton {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vault.showExpandedNote = true
                    }
                }
                Button(action: { showMarkdownPreview.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showMarkdownPreview ? "doc.richtext" : "doc.plaintext")
                            .font(.system(size: 10))
                        Text(showMarkdownPreview ? "Rich" : "Raw")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(theme.textFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.fieldBg)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            if showMarkdownPreview {
                MarkdownTextView(text: item.noteText ?? "", theme: theme, highlightText: vault.searchText)
            } else {
                SelectableText(text: item.noteText ?? "", theme: theme, highlightText: vault.searchText)
            }

            HStack {
                Spacer()
                IconButton(
                    icon: vault.copiedField == "note" ? "checkmark" : "doc.on.doc",
                    isActive: vault.copiedField == "note",
                    action: { vault.copyToClipboard(item.noteText ?? "", fieldName: "note") }
                )
            }
        }
        .padding(12)
        .background(theme.fieldBg)
        .cornerRadius(8)
    }
}

// MARK: - Re-authentication Overlay

struct ReauthOverlay: View {
    @EnvironmentObject var vault: VaultViewModel
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                    .foregroundColor(theme.accentBlueLt)

                Text("Re-authenticate")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.text)

                Text("Enter your master password to edit credentials")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)

                ZStack(alignment: .leading) {
                    if vault.reauthPassword.isEmpty {
                        Text("Master password")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                            .padding(10)
                    }
                    SecureField("", text: $vault.reauthPassword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.text)
                        .padding(10)
                        .onSubmit { vault.confirmReauth() }
                }
                .background(theme.inputBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(vault.reauthError.isEmpty ? theme.inputBorder : theme.accentRed, lineWidth: 1)
                )

                if !vault.reauthError.isEmpty {
                    Text(vault.reauthError)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.accentRed)
                }

                HStack(spacing: 8) {
                    Button(action: { vault.confirmReauth() }) {
                        HStack(spacing: 4) {
                            if vault.isReauthenticating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(vault.isReauthenticating ? "Verifying..." : "Confirm")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "3b82f6"), Color(hex: "2563eb")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(vault.isReauthenticating)

                    Button(action: { vault.cancelReauth() }) {
                        Text("Cancel")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(theme.fieldBg)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(theme.cardBg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }
}

// MARK: - Password History Section

struct PasswordHistorySection: View {
    let history: [PasswordHistoryEntry]
    @Environment(\.theme) var theme
    @EnvironmentObject var vault: VaultViewModel
    @State private var expanded = false
    @State private var revealedID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                    Text("PASSWORD HISTORY")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1)
                    Text("(\(history.count))")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(theme.textFaint)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 4) {
                    ForEach(history) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(revealedID == entry.id ? entry.password : String(repeating: "\u{2022}", count: 14))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(revealedID == entry.id ? theme.text : theme.textSecondary)
                                    .lineLimit(1)
                                Text(entry.changedAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(theme.textGhost)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                IconButton(
                                    icon: revealedID == entry.id ? "eye.slash" : "eye",
                                    isActive: false,
                                    action: { revealedID = revealedID == entry.id ? nil : entry.id }
                                )
                                IconButton(
                                    icon: vault.copiedField == "hist-\(entry.id)" ? "checkmark" : "doc.on.doc",
                                    isActive: vault.copiedField == "hist-\(entry.id)",
                                    action: { vault.copyToClipboard(entry.password, fieldName: "hist-\(entry.id)") }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.fieldBg)
                        .cornerRadius(6)
                    }
                }
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

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let text: String
    let theme: FlapsyTheme
    var highlightText: String = ""

    var body: some View {
        if var attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            let _ = Self.applyHighlight(to: &attributed, query: highlightText, theme: theme)
            Text(attributed)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.text)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SelectableText(text: text, theme: theme, highlightText: highlightText)
        }
    }

    private static func applyHighlight(to attributed: inout AttributedString, query: String, theme: FlapsyTheme) {
        guard !query.isEmpty else { return }
        let plain = String(attributed.characters).lowercased()
        let queryLower = query.lowercased()
        var searchStart = plain.startIndex
        while let range = plain.range(of: queryLower, range: searchStart..<plain.endIndex) {
            let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let attrEnd = attributed.index(attrStart, offsetByCharacters: plain.distance(from: range.lowerBound, to: range.upperBound))
            attributed[attrStart..<attrEnd].backgroundColor = theme.accentGreen.opacity(0.5)
            attributed[attrStart..<attrEnd].foregroundColor = theme.text
            searchStart = range.upperBound
        }
    }
}

// MARK: - Detail Field Row

struct DetailFieldRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil
    let copyAction: () -> Void
    let isCopied: Bool

    @Environment(\.theme) var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textFaint)
                    .tracking(1)
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(valueColor ?? theme.text)
            }
            Spacer()
            IconButton(
                icon: isCopied ? "checkmark" : "doc.on.doc",
                isActive: isCopied,
                action: copyAction
            )
        }
        .padding(12)
        .background(theme.fieldBg)
        .cornerRadius(8)
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? theme.accentGreen : theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(isActive ? theme.accentGreen.opacity(0.2) : theme.fieldBg)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selectable Text (read-only, supports text selection + Cmd+C)

struct SelectableText: View {
    let text: String
    let theme: FlapsyTheme
    var highlightText: String = ""

    var body: some View {
        SelectableTextRepresentable(text: text, theme: theme, highlightText: highlightText)
            .frame(height: Self.calculateHeight(text: text))
    }

    static func calculateHeight(text: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: 280, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return max(ceil(rect.height) + 4, 20)
    }
}

private struct SelectableTextRepresentable: NSViewRepresentable {
    let text: String
    let theme: FlapsyTheme
    var highlightText: String = ""

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor(theme.text)
        applyText(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        applyText(textView)
        textView.textColor = NSColor(theme.text)
    }

    private func applyText(_ textView: NSTextView) {
        if textView.string != text {
            textView.string = text
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        textView.defaultParagraphStyle = style
        if let storage = textView.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.paragraphStyle, value: style, range: range)
            // Remove old highlights
            storage.removeAttribute(.backgroundColor, range: range)
            // Apply search highlights
            if !highlightText.isEmpty {
                let nsText = (text as NSString).lowercased as NSString
                let query = (highlightText as NSString).lowercased as NSString
                var searchRange = NSRange(location: 0, length: nsText.length)
                let highlightColor = NSColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 0.5)
                while searchRange.location < nsText.length {
                    let found = nsText.range(of: query as String, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }
                    storage.addAttribute(.backgroundColor, value: highlightColor, range: found)
                    searchRange.location = found.location + found.length
                    searchRange.length = nsText.length - searchRange.location
                }
            }
        }
    }
}

// MARK: - TOTP Display Row

struct TOTPDisplayRow: View {
    let secret: String
    @Environment(\.theme) var theme
    @EnvironmentObject var vault: VaultViewModel
    @State private var code: String = "------"
    @State private var remaining: Int = 30
    @State private var timer: Timer?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("2FA CODE")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.textFaint)
                    .tracking(1)
                HStack(spacing: 8) {
                    Text(formatCode(code))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accentBlueLt)
                    HStack(spacing: 3) {
                        TOTPCountdownArc(remaining: remaining, period: 30)
                            .frame(width: 16, height: 16)
                        Text("\(remaining)s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(remaining <= 5 ? theme.accentRed : theme.textSecondary)
                    }
                }
            }
            Spacer()
            IconButton(
                icon: vault.copiedField == "totp" ? "checkmark" : "doc.on.doc",
                isActive: vault.copiedField == "totp",
                action: { vault.copyToClipboard(code, fieldName: "totp") }
            )
        }
        .padding(12)
        .background(theme.fieldBg)
        .cornerRadius(8)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func formatCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    private func refreshCode() {
        if let result = TOTPService.generate(secret: secret) {
            code = result.code
            remaining = result.remaining
        }
    }

    private func startTimer() {
        refreshCode()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            refreshCode()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - TOTP Countdown Arc

struct TOTPCountdownArc: View {
    let remaining: Int
    let period: Int
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.fieldBg, lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / CGFloat(period))
                .stroke(
                    remaining <= 5 ? theme.accentRed : theme.accentBlue,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
        }
    }
}
