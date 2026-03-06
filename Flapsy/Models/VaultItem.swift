import Foundation

enum ItemType: String, Codable, CaseIterable {
    case login
    case card
    case note
}

struct VaultItem: Codable, Identifiable {
    let id: UUID
    var type: ItemType
    var name: String
    var category: String
    var isFavorite: Bool
    var createdAt: Date
    var modifiedAt: Date

    // Login fields
    var url: String?
    var username: String?
    var password: String?
    var totpSecret: String?

    // Card fields
    var cardType: String?
    var cardHolder: String?
    var cardNumber: String?
    var expiry: String?
    var cvv: String?
    var cardNotes: String?

    static let cardTypes = ["Visa", "Mastercard", "Amex", "Discover", "UnionPay"]

    // Note fields
    var noteText: String?

    // Soft delete
    var deletedAt: Date?

    // Computed
    var subtitle: String {
        switch type {
        case .login:
            return username ?? ""
        case .card:
            return cardHolder ?? ""
        case .note:
            return String((noteText ?? "").prefix(40))
        }
    }

    var lastUsedDisplay: String {
        let interval = Date().timeIntervalSince(modifiedAt)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        if days < 7 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        let weeks = days / 7
        return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
    }
}

extension VaultItem {
    static func newLogin(name: String, url: String, username: String, password: String, category: String, totpSecret: String? = nil) -> VaultItem {
        VaultItem(
            id: UUID(), type: .login, name: name, category: category,
            isFavorite: false, createdAt: Date(), modifiedAt: Date(),
            url: url, username: username, password: password,
            totpSecret: totpSecret
        )
    }

    static func newCard(name: String, cardType: String, cardHolder: String, cardNumber: String, expiry: String, cvv: String, cardNotes: String, category: String) -> VaultItem {
        VaultItem(
            id: UUID(), type: .card, name: name, category: category,
            isFavorite: false, createdAt: Date(), modifiedAt: Date(),
            cardType: cardType.isEmpty ? nil : cardType,
            cardHolder: cardHolder, cardNumber: cardNumber, expiry: expiry, cvv: cvv,
            cardNotes: cardNotes.isEmpty ? nil : cardNotes
        )
    }

    static func newNote(name: String, noteText: String, category: String) -> VaultItem {
        VaultItem(
            id: UUID(), type: .note, name: name, category: category,
            isFavorite: false, createdAt: Date(), modifiedAt: Date(),
            noteText: noteText
        )
    }
}
