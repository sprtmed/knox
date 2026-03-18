import SwiftUI

struct AddItemView: View {
    @EnvironmentObject var vault: VaultViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @Environment(\.theme) var theme
    @State private var expandedNoteAutoOpened = false

    var body: some View {
        if vault.showExpandedNote {
            expandedNoteSubpage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                if vault.newSaved {
                    savedConfirmation
                } else {
                    addForm
                }
            }
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var expandedNoteSubpage: some View {
        ExpandedNoteView(
            text: expandedNoteBinding,
            title: vault.newType == .note ? "SECURE NOTE" : "NOTES",
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    vault.showExpandedNote = false
                }
            }
        )
    }

    private var expandedNoteBinding: Binding<String> {
        switch vault.newType {
        case .login: return $vault.newLoginNotes
        case .card: return $vault.newCardNotes
        case .note: return $vault.newNoteText
        }
    }

    // MARK: - Saved Confirmation

    private var savedConfirmation: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 50)
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.accentGreen.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
            }
            .scaleEffect(vault.newSaved ? 1.0 : 0.5)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: vault.newSaved)

            Text("Saved to Vault")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.accentGreen)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add Form

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Type selector
            VStack(alignment: .leading, spacing: 5) {
                FormLabel("ITEM TYPE")
                HStack(spacing: 4) {
                    TypePill(type: .login, label: "\u{1F511} Login", selectedType: $vault.newType)
                    TypePill(type: .card, label: "\u{1F4B3} Card", selectedType: $vault.newType)
                    TypePill(type: .note, label: "\u{1F4DD} Note", selectedType: $vault.newType)
                }
            }

            // Name
            VStack(alignment: .leading, spacing: 5) {
                FormLabel("NAME")
                FormTextField(
                    placeholder: namePlaceholder,
                    text: $vault.newName
                )
            }

            // Type-specific fields
            switch vault.newType {
            case .login:
                loginFields
            case .card:
                cardFields
            case .note:
                noteFields
            }

            // Category picker
            VStack(alignment: .leading, spacing: 5) {
                FormLabel("CATEGORY")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(vault.categories) { cat in
                            Button(action: { vault.newCategory = cat.key }) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(hex: cat.color))
                                        .frame(width: 8, height: 8)
                                    Text(cat.label)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(vault.newCategory == cat.key ? theme.accentBlueLt : theme.textMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(vault.newCategory == cat.key ? theme.pillBg : Color.clear)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            vault.newCategory == cat.key ? theme.accentBlue.opacity(0.27) : theme.inputBorder,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Save button
            Button(action: { vault.saveNewItem() }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                    Text("Encrypt & Save")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "3b82f6"), Color(hex: "2563eb")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .opacity(vault.canSaveNewItem ? 1.0 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!vault.canSaveNewItem)
            .padding(.top, 4)
        }
    }

    // MARK: - Login Fields

    @ViewBuilder
    private var loginFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            FormLabel("DOMAIN / URL")
            FormTextField(placeholder: "e.g. github.com", text: $vault.newUrl)
        }
        VStack(alignment: .leading, spacing: 5) {
            FormLabel("USERNAME / EMAIL")
            FormTextField(placeholder: "e.g. user@email.com", text: $vault.newUsername)
        }
        VStack(alignment: .leading, spacing: 5) {
            FormLabel("PASSWORD")
            HStack(spacing: 6) {
                ZStack(alignment: .trailing) {
                    if vault.showNewPassword {
                        FormTextField(placeholder: "Enter or generate\u{2026}", text: $vault.newPassword)
                    } else {
                        ZStack(alignment: .leading) {
                            if vault.newPassword.isEmpty {
                                Text("Enter or generate\u{2026}")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(theme.textMuted)
                                    .padding(10)
                            }
                            SecureField("", text: $vault.newPassword)
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
                    Button(action: { vault.showNewPassword.toggle() }) {
                        Text(vault.showNewPassword ? "Hide" : "Show")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textFaint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }

                Button(action: {
                    vault.newPassword = GeneratorViewModel.secureRandomPassword()
                }) {
                    Text("\u{26A1} Gen")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accentPurple)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(theme.accentPurple.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.accentPurple.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

        VStack(alignment: .leading, spacing: 5) {
            FormLabel("2FA SECRET (OPTIONAL)")
            FormTextField(placeholder: "Paste base32 key or otpauth:// URI", text: $vault.newTotpSecret)
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
            TextEditor(text: $vault.newLoginNotes)
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
            if settings.alwaysExpandNotes && !expandedNoteAutoOpened {
                expandedNoteAutoOpened = true
                vault.showExpandedNote = true
            }
        }

            // Strength bar
            if !vault.newPassword.isEmpty {
                let strength = vault.newPasswordStrength
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.fieldBg)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PasswordStrength.color(for: strength))
                                .frame(width: geo.size.width * CGFloat(strength) / 100)
                                .animation(.easeInOut(duration: 0.3), value: strength)
                        }
                    }
                    .frame(height: 4)

                    Text("\(PasswordStrength.label(for: strength)) \(strength)%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(PasswordStrength.color(for: strength))
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Card Fields

    @ViewBuilder
    private var cardFields: some View {
        HStack {
            Text("Card Type")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.text)
            Spacer()
            FlapsyDropdown(
                value: vault.newCardType.isEmpty ? "Select type" : vault.newCardType,
                options: VaultItem.cardTypes,
                onChange: { vault.newCardType = $0 },
                width: 190
            )
        }
        .padding(.vertical, 4)
        .zIndex(10)
        VStack(alignment: .leading, spacing: 5) {
            FormLabel("CARDHOLDER NAME")
            FormTextField(placeholder: "e.g. John Doe", text: $vault.newCardHolder)
        }
        VStack(alignment: .leading, spacing: 5) {
            FormLabel("CARD NUMBER")
            FormTextField(placeholder: "0000 0000 0000 0000", text: $vault.newCardNumber)
                .onChange(of: vault.newCardNumber) { val in
                    let formatted = VaultViewModel.formatCardNumber(val)
                    if formatted != val { vault.newCardNumber = formatted }
                }
        }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                FormLabel("EXPIRY")
                FormTextField(placeholder: "MM/YY", text: $vault.newExpiry)
                    .onChange(of: vault.newExpiry) { val in
                        let formatted = VaultViewModel.formatExpiry(val)
                        if formatted != val { vault.newExpiry = formatted }
                    }
            }
            VStack(alignment: .leading, spacing: 5) {
                FormLabel("CVV")
                ZStack(alignment: .leading) {
                    if vault.newCvv.isEmpty {
                        Text("\u{2022}\u{2022}\u{2022}")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                            .padding(10)
                    }
                    SecureField("", text: $vault.newCvv)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.text)
                        .padding(10)
                        .onChange(of: vault.newCvv) { val in
                            let formatted = VaultViewModel.formatCVV(val)
                            if formatted != val { vault.newCvv = formatted }
                        }
                }
                .background(theme.inputBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
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
            TextEditor(text: $vault.newCardNotes)
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
            if settings.alwaysExpandNotes && !expandedNoteAutoOpened {
                expandedNoteAutoOpened = true
                vault.showExpandedNote = true
            }
        }
    }

    // MARK: - Note Fields

    @ViewBuilder
    private var noteFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FormLabel("SECURE NOTE")
                Spacer()
                NoteExpandButton {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vault.showExpandedNote = true
                    }
                }
            }
            TextEditor(text: $vault.newNoteText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 120)
                .background(theme.inputBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
        }
        .onAppear {
            if settings.alwaysExpandNotes && !expandedNoteAutoOpened {
                expandedNoteAutoOpened = true
                vault.showExpandedNote = true
            }
        }
    }

    private var namePlaceholder: String {
        switch vault.newType {
        case .login: return "e.g. GitHub"
        case .card: return "e.g. Visa \u{2022}\u{2022}\u{2022}\u{2022} 1234"
        case .note: return "e.g. Recovery Codes"
        }
    }
}

// MARK: - Form Helpers

struct FormLabel: View {
    let text: String
    @Environment(\.theme) var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textSecondary)
            .tracking(1)
    }
}

struct FormTextField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.theme) var theme

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
                    .padding(10)
            }
            TextField("", text: $text)
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
}

struct TypePill: View {
    let type: ItemType
    let label: String
    @Binding var selectedType: ItemType
    @Environment(\.theme) var theme

    var body: some View {
        Button(action: { selectedType = type }) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(selectedType == type ? theme.accentBlueLt : theme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(selectedType == type ? theme.pillBg : Color.clear)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            selectedType == type ? theme.accentBlue.opacity(0.27) : theme.inputBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
