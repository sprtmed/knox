import Foundation
import Combine
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.knox.app", category: "Vault")

// MARK: - Brute-Force Persistence

/// Persists failed-attempt count and lockout-end timestamp to UserDefaults
/// so that quitting/relaunching cannot reset the brute-force counter.
private enum BruteForceState {
    private static let defaults = UserDefaults.standard
    private static let attemptsKey  = "com.knox.bruteforce.failedAttempts"
    private static let lockoutEndKey = "com.knox.bruteforce.lockoutEnd"

    static var persistedFailedAttempts: Int {
        get { defaults.integer(forKey: attemptsKey) }
        set { defaults.set(newValue, forKey: attemptsKey) }
    }

    static var lockoutEndDate: Date? {
        get {
            let ts = defaults.double(forKey: lockoutEndKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            if let d = newValue {
                defaults.set(d.timeIntervalSince1970, forKey: lockoutEndKey)
            } else {
                defaults.removeObject(forKey: lockoutEndKey)
            }
        }
    }
}

enum AppScreen: Equatable {
    case lock
    case setup       // First-launch: create master password
    case vault
}

enum VaultPanel {
    case list
    case addNew
    case generator
    case tags
    case settings
    case health
    case trash
}

final class VaultViewModel: ObservableObject {
    // MARK: - App State
    @Published var currentScreen: AppScreen = .lock
    @Published var currentPanel: VaultPanel = .list
    @Published var isUnlocked: Bool = false
    @Published var isLoading: Bool = false

    // MARK: - Lock Screen
    @Published var masterPasswordInput: String = ""
    @Published var lockError: Bool = false
    @Published var lockErrorMessage: String = ""
    @Published var shakeError: Bool = false
    @Published var isLockedOut: Bool = false
    @Published var lockoutRemainingSeconds: Int = 0
    private var failedAttempts: Int {
        didSet { BruteForceState.persistedFailedAttempts = failedAttempts }
    }
    private var lockoutTimer: Timer?

    // MARK: - Secret Key Recovery (v2 vault, Keychain lost)
    @Published var needsSecretKeyRecovery: Bool = false
    @Published var secretKeyRecoveryInput: String = ""
    @Published var secretKeyRecoveryError: String = ""

    // MARK: - Secret Key Display (after creation or migration)
    @Published var showSecretKey: Bool = false
    @Published var displayedSecretKey: String = ""

    // MARK: - Setup Screen (first launch)
    @Published var setupPassword: String = ""
    @Published var setupConfirm: String = ""
    @Published var setupError: String = ""

    // MARK: - Vault Data
    @Published var items: [VaultItem] = []
    @Published var categories: [VaultCategory] = []

    // MARK: - Search & Filters
    @Published var searchText: String = ""
    @Published var typeFilter: ItemType? = nil
    @Published var activeCategory: String = "all"
    @Published var showFavoritesOnly: Bool = false

    // MARK: - Selection
    @Published var selectedItemID: UUID? = nil
    @Published var showPassword: Bool = false
    @Published var showCardNumber: Bool = false
    @Published var showCVV: Bool = false

    // MARK: - Copy Feedback
    @Published var copiedField: String? = nil

    // MARK: - Add New Item
    @Published var newType: ItemType = .login
    @Published var newName: String = ""
    @Published var newUrl: String = ""
    @Published var newUsername: String = ""
    @Published var newPassword: String = ""
    @Published var newCategory: String = ""
    @Published var showNewPassword: Bool = false
    @Published var newSaved: Bool = false
    @Published var newCardType: String = ""
    @Published var newCardHolder: String = ""
    @Published var newCardNumber: String = ""
    @Published var newExpiry: String = ""
    @Published var newCvv: String = ""
    @Published var newCardNotes: String = ""
    @Published var newNoteText: String = ""
    @Published var newTotpSecret: String = ""
    @Published var newLoginNotes: String = ""

    // MARK: - Expanded Note
    @Published var showExpandedNote: Bool = false

    // MARK: - Edit Item
    @Published var isEditingItem: Bool = false
    @Published var editName: String = ""
    @Published var editUrl: String = ""
    @Published var editUsername: String = ""
    @Published var editPassword: String = ""
    @Published var editCategory: String = ""
    @Published var editCardType: String = ""
    @Published var editCardHolder: String = ""
    @Published var editCardNumber: String = ""
    @Published var editExpiry: String = ""
    @Published var editCvv: String = ""
    @Published var editCardNotes: String = ""
    @Published var editNoteText: String = ""
    @Published var editTotpSecret: String = ""
    @Published var editLoginNotes: String = ""
    @Published var showEditPassword: Bool = false

    // MARK: - Category Manager
    @Published var newTagName: String = ""
    @Published var newTagColor: String = VaultCategory.availableColors[0]

    // MARK: - Import/Export
    @Published var importPreview: ImportService.ImportResult? = nil
    @Published var importError: String = ""
    @Published var isImporting: Bool = false
    @Published var importProgress: String = ""
    @Published var importCategory: String = ""  // "" = keep original, otherwise category key
    @Published var showImportPreview: Bool = false
    @Published var showExportSheet: Bool = false
    @Published var exportError: String = ""
    @Published var isExporting: Bool = false
    @Published var exportPasswordInput: String = ""
    @Published var exportPasswordConfirm: String = ""
    @Published var csvExportMasterPassword: String = ""
    @Published var csvExportConfirmed: Bool = false

    // MARK: - Change Password
    @Published var changeOldPassword: String = ""
    @Published var changeNewPassword: String = ""
    @Published var changeConfirmPassword: String = ""
    @Published var changePasswordError: String = ""
    @Published var changePasswordSuccess: Bool = false
    @Published var isChangingPassword: Bool = false

    // MARK: - Edit Re-authentication
    @Published var showReauthPrompt: Bool = false
    @Published var reauthPassword: String = ""
    @Published var reauthError: String = ""
    @Published var isReauthenticating: Bool = false
    private var reauthPendingItem: VaultItem?

    // MARK: - Vault Reset
    @Published var showResetConfirmation: Bool = false
    @Published var resetConfirmText: String = ""
    @Published var isResetting: Bool = false

    // MARK: - Start Fresh (lock screen vault overwrite)
    @Published var showStartFreshConfirmation: Bool = false
    @Published var startFreshConfirmText: String = ""

    // MARK: - Biometric
    @Published var showBiometricPrompt: Bool = false
    @Published var biometricFailed: Bool = false
    @Published var showEnableBiometricPrompt: Bool = false

    // MARK: - Onboarding
    @Published var isOnboarding: Bool = false
    @Published var onboardingPasswordCreated: Bool = false

    // MARK: - Search
    @Published var isSearchFocused: Bool = false

    private let storage = StorageService.shared
    private let encryption = EncryptionService.shared
    private var cancellables = Set<AnyCancellable>()
    private var autoSaveDebounce: AnyCancellable?

    /// Reference to settings VM so we can persist settings with vault
    weak var settingsViewModel: SettingsViewModel?

    // MARK: - Init

    init() {
        // Restore persisted brute-force counter across app restarts
        failedAttempts = BruteForceState.persistedFailedAttempts
        checkFirstLaunch()
        restoreLockoutIfNeeded()
    }

    /// Determines whether to show lock screen or setup screen.
    /// Uses vaultFileExists (not vaultExists) so that a lost Keychain/salt
    /// still shows the lock screen instead of the setup screen.
    func checkFirstLaunch() {
        if storage.vaultFileExists {
            currentScreen = .lock
        } else {
            currentScreen = .setup
            isOnboarding = true
        }
    }


    // MARK: - Computed

    var selectedItem: VaultItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    var activeItems: [VaultItem] {
        items.filter { $0.deletedAt == nil }
    }

    var trashedItems: [VaultItem] {
        items.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var filteredItems: [VaultItem] {
        let filtered = activeItems.filter { item in
            let matchesCategory = activeCategory == "all" || item.category == activeCategory
            let matchesType = typeFilter == nil || item.type == typeFilter
            let matchesFavorite = !showFavoritesOnly || item.isFavorite
            return matchesCategory && matchesType && matchesFavorite
        }

        if searchText.isEmpty {
            return filtered.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        return filtered.compactMap { item -> (VaultItem, Int)? in
            let query = searchText.lowercased()
            let nameLower = item.name.lowercased()
            let userLower = (item.username ?? "").lowercased()
            let noteLower = (item.noteText ?? item.loginNotes ?? "").lowercased()

            // Substring matches on name, username & noteText — always include, ranked highest
            let nameContains = nameLower.contains(query)
            let userContains = userLower.contains(query)
            let noteContains = noteLower.contains(query)

            if nameContains || userContains || noteContains {
                var score = 100
                if nameLower.hasPrefix(query) { score += 50 }
                else if nameContains { score += 25 }
                if userContains { score += 10 }
                if noteContains { score += 5 }
                return (item, score)
            }

            // Fuzzy matching on name & username only (URLs contain too much noise)
            let nameScore = FuzzySearch.match(query: searchText, in: item.name)?.score ?? 0
            let userScore = FuzzySearch.match(query: searchText, in: item.username ?? "")?.score ?? 0
            let bestScore = max(nameScore, userScore)
            let minScore = max(searchText.count * 3, 5)
            guard bestScore >= minScore else { return nil }
            return (item, bestScore)
        }
        .sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.isFavorite != b.0.isFavorite { return a.0.isFavorite }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        .map(\.0)
    }

    var newPasswordStrength: Int {
        PasswordStrength.calculate(newPassword)
    }

    var setupPasswordStrength: Int {
        PasswordStrength.calculate(setupPassword)
    }

    var canSaveNewItem: Bool {
        guard !newName.isEmpty else { return false }
        switch newType {
        case .login: return !newUrl.isEmpty
        case .card: return !newCardNumber.isEmpty
        case .note: return !newNoteText.isEmpty
        }
    }

    // MARK: - Vault Health (cached, updated via Combine on $items)

    @Published var weakPasswordItemIDs: Set<UUID> = []
    @Published var reusedPasswordGroups: [[VaultItem]] = []
    @Published var reusedPasswordItemIDs: Set<UUID> = []
    @Published var duplicateLoginGroups: [[VaultItem]] = []
    @Published var duplicateLoginItemIDs: Set<UUID> = []
    @Published var flaggedItemIDs: Set<UUID> = []
    @Published var healthScore: Int = 100
    private var healthDebounce: AnyCancellable?

    // Breach detection (HIBP)
    @Published var compromisedItemIDs: Set<UUID> = []
    @Published var breachOccurrences: [UUID: Int] = [:]  // itemID -> breach count
    @Published var isCheckingBreaches: Bool = false
    @Published var breachCheckError: String = ""
    @Published var lastBreachCheckDate: Date? = nil
    private var breachCheckTask: Task<Void, Never>?

    func recomputeHealth() {
        let currentItems = activeItems

        let weak = Set<UUID>(
            currentItems.compactMap { item -> UUID? in
                guard item.type == .login, let pw = item.password, !pw.isEmpty else { return nil }
                return PasswordStrength.calculate(pw) < 50 ? item.id : nil
            }
        )

        let loginItems = currentItems.filter { $0.type == .login && $0.password != nil && !$0.password!.isEmpty }
        let pwGrouped = Dictionary(grouping: loginItems) { $0.password! }
        let reusedGroups = pwGrouped.values.filter { $0.count >= 2 }.sorted { $0.count > $1.count }
        let reusedIDs = Set<UUID>(reusedGroups.flatMap { $0.map(\.id) })

        let dupLoginItems = currentItems.filter {
            $0.type == .login && $0.url != nil && !$0.url!.isEmpty &&
            $0.username != nil && !$0.username!.isEmpty
        }
        let dupGrouped = Dictionary(grouping: dupLoginItems) { item in
            "\(item.url!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(item.username!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let dupGroups = dupGrouped.values.filter { $0.count >= 2 }.sorted { $0.count > $1.count }
        let dupIDs = Set<UUID>(dupGroups.flatMap { $0.map(\.id) })

        // Remove deleted or passwordless items from breach results
        let checkableIDs = Set(currentItems.filter { $0.type == .login && $0.password != nil && !$0.password!.isEmpty }.map(\.id))
        compromisedItemIDs = compromisedItemIDs.intersection(checkableIDs)
        breachOccurrences = breachOccurrences.filter { checkableIDs.contains($0.key) }

        let flagged = weak.union(reusedIDs).union(dupIDs).union(compromisedItemIDs)

        let logins = currentItems.filter { $0.type == .login && $0.password != nil && !$0.password!.isEmpty }
        let score: Int
        if logins.isEmpty {
            score = 100
        } else {
            // Compromised passwords get double penalty weight
            var penalty = 0.0
            for login in logins {
                if compromisedItemIDs.contains(login.id) {
                    penalty += 2.0  // severe: known breach
                } else if weak.contains(login.id) || reusedIDs.contains(login.id) {
                    penalty += 1.0
                } else if dupIDs.contains(login.id) {
                    penalty += 0.5
                }
            }
            let rawScore = max(0, Double(logins.count) - penalty) / Double(logins.count) * 100
            score = Int(round(rawScore))
        }

        weakPasswordItemIDs = weak
        reusedPasswordGroups = reusedGroups
        reusedPasswordItemIDs = reusedIDs
        duplicateLoginGroups = dupGroups
        duplicateLoginItemIDs = dupIDs
        flaggedItemIDs = flagged
        healthScore = score
    }

    func setupHealthMonitor() {
        healthDebounce?.cancel()
        healthDebounce = $items
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeHealth()
            }
        recomputeHealth()
    }

    /// Check all vault passwords against HIBP breach database.
    /// Only runs if the user has opted in via Settings.
    func runBreachCheck() {
        guard settingsViewModel?.breachCheckEnabled == true else { return }

        breachCheckTask?.cancel()
        breachCheckTask = Task { @MainActor in
            isCheckingBreaches = true
            breachCheckError = ""

            let loginItems = activeItems.compactMap { item -> (id: UUID, password: String)? in
                guard item.type == .login, let pw = item.password, !pw.isEmpty else { return nil }
                return (id: item.id, password: pw)
            }

            let results = await HIBPService.checkVault(items: loginItems)

            guard !Task.isCancelled else {
                isCheckingBreaches = false
                return
            }

            compromisedItemIDs = Set(results.map(\.itemID))
            breachOccurrences = Dictionary(uniqueKeysWithValues: results.map { ($0.itemID, $0.occurrences) })
            lastBreachCheckDate = Date()
            isCheckingBreaches = false
            recomputeHealth()
        }
    }

    func navigateToItem(_ id: UUID) {
        searchText = ""
        typeFilter = nil
        activeCategory = "all"
        showFavoritesOnly = false
        currentPanel = .list
        selectedItemID = id
    }

    // MARK: - Secret Key Display

    /// Formats the current Secret Key for display. Returns nil if no key exists.
    var formattedSecretKey: String? {
        guard let keyData = SecretKeyService.shared.retrieveSecretKey() else { return nil }
        return SecretKeyService.formatForDisplay(keyData)
    }

    func copySecretKey() {
        guard let formatted = formattedSecretKey else { return }
        ClipboardService.shared.copy(formatted, clearAfter: 60)
        copiedField = "secretKey"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedField == "secretKey" { self?.copiedField = nil }
        }
    }

    func dismissSecretKeyDisplay() {
        showSecretKey = false
        displayedSecretKey = ""
    }

    // MARK: - First Launch: Create Master Password (v2 — Argon2id + Secret Key)

    func createMasterPassword() {
        // Safety: refuse to overwrite an existing vault
        guard !storage.vaultFileExists else {
            setupError = "A vault already exists. Use \"Start Fresh\" from the lock screen first."
            return
        }

        let password = setupPassword.trimmingCharacters(in: .whitespaces)
        let confirm = setupConfirm.trimmingCharacters(in: .whitespaces)
        setupPassword = ""
        setupConfirm = ""

        guard !password.isEmpty else {
            setupError = "Password cannot be empty"
            return
        }
        guard password.count >= 12 else {
            setupError = "Password must be at least 12 characters"
            return
        }
        guard PasswordStrength.calculate(password) >= PasswordStrength.minimumRequired else {
            setupError = "Password is too weak — use a mix of upper/lowercase, numbers, and symbols"
            return
        }
        guard password == confirm else {
            setupError = "Passwords do not match"
            return
        }

        isLoading = true
        setupError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let (vaultData, secretKey) = try self.storage.createNewVault(masterPassword: password)
                let secretKeyDisplay = SecretKeyService.formatForDisplay(secretKey)
                DispatchQueue.main.async {
                    self.items = vaultData.items
                    self.categories = vaultData.categories
                    self.settingsViewModel?.loadFromVaultSettings(vaultData.settings)
                    self.isUnlocked = true
                    self.isLoading = false
                    self.setupAutoSave()

                    // Show Secret Key to user
                    self.displayedSecretKey = secretKeyDisplay
                    self.showSecretKey = true

                    if self.isOnboarding {
                        self.onboardingPasswordCreated = true
                    } else {
                        self.currentScreen = .vault
                        self.currentPanel = .list
                        self.showFavoritesOnly = self.settingsViewModel?.defaultFavoritesFilter ?? false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.setupError = "Failed to create vault: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Unlock

    /// Progressive lockout delay: 0, 0, 0, 2s, 4s, 8s, 16s, 30s, 30s, ...
    private func lockoutDuration(for attempts: Int) -> Int {
        guard attempts >= 3 else { return 0 }
        return min(30, Int(pow(2.0, Double(attempts - 2))))
    }

    func unlock() {
        let password = masterPasswordInput
        masterPasswordInput = ""

        guard !password.isEmpty else {
            triggerLockError("Enter your master password")
            return
        }

        guard !isLockedOut else { return }

        isLoading = true
        lockError = false
        lockErrorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let (vaultData, needsMigration) = try self.storage.unlockVault(masterPassword: password)
                DispatchQueue.main.async {
                    self.failedAttempts = 0
                    BruteForceState.lockoutEndDate = nil
                    self.items = vaultData.items
                    self.categories = vaultData.categories
                    self.settingsViewModel?.loadFromVaultSettings(vaultData.settings)
                    self.isUnlocked = true
                    self.isLoading = false
                    self.currentScreen = .vault
                    self.currentPanel = .list
                    self.showFavoritesOnly = self.settingsViewModel?.defaultFavoritesFilter ?? false
                    self.lockError = false
                    self.biometricFailed = false
                    self.needsSecretKeyRecovery = false
                    self.setupAutoSave()

                    // Refresh biometric key (must run before sync check so
                    // the key is re-stored under the current access group)
                    if self.settingsViewModel?.biometricEnabled == true,
                       var keyData = self.encryption.currentKeyData {
                        KeychainService.shared.storeDerivedKey(keyData)
                        keyData.resetBytes(in: 0..<keyData.count)
                        KeychainService.biometricEnabledFlag = true
                    }

                    // Sync biometric state: if store failed, disable biometric
                    if self.settingsViewModel?.biometricEnabled == true &&
                       !KeychainService.shared.hasDerivedKey {
                        self.settingsViewModel?.biometricEnabled = false
                        KeychainService.biometricEnabledFlag = false
                    }

                    // If v1 vault, migrate to v2 (Argon2id + Secret Key)
                    if needsMigration {
                        self.migrateToV2(password: password, vaultData: vaultData)
                    }
                }
            } catch let error as EncryptionError where error == .secretKeyMissing {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.needsSecretKeyRecovery = true
                    self.triggerLockError("Secret Key not found — enter it from your Emergency Kit")
                }
            } catch let error as EncryptionError where error == .invalidPassword {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.failedAttempts += 1
                    let delay = self.lockoutDuration(for: self.failedAttempts)
                    if delay > 0 {
                        self.startLockout(seconds: delay)
                        self.triggerLockError("Incorrect password — try again in \(delay)s")
                    } else {
                        self.triggerLockError("Incorrect password")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.triggerLockError("Unlock failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Secret Key Recovery Unlock

    func unlockWithRecoveredSecretKey() {
        let password = masterPasswordInput
        let skInput = secretKeyRecoveryInput
        masterPasswordInput = ""
        secretKeyRecoveryInput = ""

        guard !password.isEmpty else {
            secretKeyRecoveryError = "Enter your master password"
            return
        }
        guard !skInput.isEmpty else {
            secretKeyRecoveryError = "Enter your Secret Key"
            return
        }
        guard let secretKey = SecretKeyService.parseFromDisplay(skInput) else {
            secretKeyRecoveryError = "Invalid Secret Key format"
            return
        }

        isLoading = true
        secretKeyRecoveryError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let vaultData = try self.storage.unlockVault(masterPassword: password, recoveredSecretKey: secretKey)
                DispatchQueue.main.async {
                    self.failedAttempts = 0
                    self.items = vaultData.items
                    self.categories = vaultData.categories
                    self.settingsViewModel?.loadFromVaultSettings(vaultData.settings)
                    self.isUnlocked = true
                    self.isLoading = false
                    self.currentScreen = .vault
                    self.currentPanel = .list
                    self.needsSecretKeyRecovery = false
                    self.setupAutoSave()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.secretKeyRecoveryError = "Incorrect password or Secret Key"
                }
            }
        }
    }

    // MARK: - V1 → V2 Migration

    /// Migrates a v1 vault to v2 (Argon2id + Secret Key) in the background.
    /// Called after a successful v1 unlock while the password is still available.
    private func migrateToV2(password: String, vaultData: VaultData) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let secretKey = try self.storage.migrateToV2(masterPassword: password, vault: vaultData)
                let display = SecretKeyService.formatForDisplay(secretKey)

                // Update biometric key with the new derived key
                if self.settingsViewModel?.biometricEnabled == true,
                   var keyData = self.encryption.currentKeyData {
                    KeychainService.shared.storeDerivedKey(keyData)
                    keyData.resetBytes(in: 0..<keyData.count)
                }

                DispatchQueue.main.async {
                    self.displayedSecretKey = display
                    self.showSecretKey = true
                }
            } catch {
                logger.error("V2 migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startLockout(seconds: Int) {
        isLockedOut = true
        lockoutRemainingSeconds = seconds
        BruteForceState.lockoutEndDate = Date().addingTimeInterval(Double(seconds))
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.lockoutRemainingSeconds -= 1
            if self.lockoutRemainingSeconds <= 0 {
                timer.invalidate()
                self.lockoutTimer = nil
                self.isLockedOut = false
                BruteForceState.lockoutEndDate = nil
            }
        }
    }

    /// Restores an active lockout that was interrupted by an app restart.
    private func restoreLockoutIfNeeded() {
        guard let endDate = BruteForceState.lockoutEndDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded(.up))
        if remaining > 0 {
            startLockout(seconds: remaining)
        } else {
            // Lockout expired while app was closed — clear it
            BruteForceState.lockoutEndDate = nil
        }
    }

    private func triggerLockError(_ message: String) {
        lockError = true
        lockErrorMessage = message
        shakeError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.shakeError = false
        }
    }

    // MARK: - Lock

    func lock() {
        persistVault()

        // Re-store key with current SecAccessControl (biometric ACL) before wiping.
        // Migrates pre-audit keys that lack biometric protection.
        if self.settingsViewModel?.biometricEnabled == true,
           var keyData = encryption.currentKeyData {
            KeychainService.shared.storeDerivedKey(keyData)
            keyData.resetBytes(in: 0..<keyData.count)
        }

        storage.lockVault()

        isUnlocked = false
        currentScreen = .lock
        selectedItemID = nil
        searchText = ""
        activeCategory = "all"
        typeFilter = nil
        currentPanel = .list

        items = []
        categories = []
        masterPasswordInput = ""

        // Clear sensitive add-new fields
        newPassword = ""
        newCardNumber = ""
        newCvv = ""
        newCardNotes = ""
        newNoteText = ""
        newTotpSecret = ""
        newLoginNotes = ""

        // Clear sensitive edit fields
        editPassword = ""
        editCardNumber = ""
        editCvv = ""
        editCardNotes = ""
        editNoteText = ""
        editTotpSecret = ""
        editLoginNotes = ""
        isEditingItem = false

        // Clear re-auth state
        showReauthPrompt = false
        reauthPassword = ""
        reauthError = ""
        reauthPendingItem = nil

        // Clear sensitive export/change-password fields
        exportPasswordInput = ""
        exportPasswordConfirm = ""
        csvExportMasterPassword = ""
        changeOldPassword = ""
        changeNewPassword = ""
        changeConfirmPassword = ""

        // Clear clipboard if it still holds a copied secret
        ClipboardService.shared.forceClearIfOwned()

        autoSaveDebounce?.cancel()
        autoSaveDebounce = nil
        healthDebounce?.cancel()
        healthDebounce = nil
        breachCheckTask?.cancel()
        breachCheckTask = nil
        compromisedItemIDs = []
        breachOccurrences = [:]
        isCheckingBreaches = false
        lastBreachCheckDate = nil
    }

    // MARK: - Persist Vault (encrypt & write to disk)

    func persistVault() {
        guard isUnlocked, encryption.hasKey else { return }

        let settings = settingsViewModel?.toVaultSettings() ?? VaultSettings.defaults
        let vault = VaultData(items: items, categories: categories, settings: settings)

        do {
            try storage.saveVault(vault)
        } catch {
            logger.error("Failed to persist vault: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupAutoSave() {
        autoSaveDebounce?.cancel()

        autoSaveDebounce = Publishers.Merge(
            $items.map { _ in () },
            $categories.map { _ in () }
        )
        .dropFirst()
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.persistVault()
        }

        setupHealthMonitor()
        purgeExpiredTrash()
        SecretKeyService.shared.migrateToSecureEnclaveIfNeeded()
        runBreachCheck()
    }

    // MARK: - CRUD Actions

    func toggleFavorite(_ id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isFavorite.toggle()
            items[index].modifiedAt = Date()
        }
    }

    func copyToClipboard(_ value: String, fieldName: String) {
        let clearSeconds = settingsViewModel?.clipboardClearEnabled == true
            ? Int(settingsViewModel?.clipboardClearSeconds ?? 30)
            : nil
        ClipboardService.shared.copy(value, clearAfter: clearSeconds)
        copiedField = fieldName
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedField == fieldName {
                self?.copiedField = nil
            }
        }
    }

    func saveNewItem() {
        guard canSaveNewItem else { return }

        let item: VaultItem
        switch newType {
        case .login:
            let totp = TOTPService.extractSecret(from: newTotpSecret)
            let notes = newLoginNotes.isEmpty ? nil : newLoginNotes
            item = .newLogin(name: newName, url: newUrl, username: newUsername, password: newPassword, category: newCategory, totpSecret: totp, loginNotes: notes)
        case .card:
            item = .newCard(name: newName, cardType: newCardType, cardHolder: newCardHolder, cardNumber: newCardNumber, expiry: newExpiry, cvv: newCvv, cardNotes: newCardNotes, category: newCategory)
        case .note:
            item = .newNote(name: newName, noteText: newNoteText, category: newCategory)
        }

        items.insert(item, at: 0)
        newSaved = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.currentPanel = .list
            self?.resetNewItem()
        }
    }

    func resetNewItem() {
        newType = .login
        newName = ""
        newUrl = ""
        newUsername = ""
        newPassword = ""
        newCategory = "personal"
        showNewPassword = false
        newSaved = false
        newCardType = ""
        newCardHolder = ""
        newCardNumber = ""
        newExpiry = ""
        newCvv = ""
        newCardNotes = ""
        newNoteText = ""
        newTotpSecret = ""
        newLoginNotes = ""
    }

    func navigateToPanel(_ panel: VaultPanel) {
        let leavingHealth = currentPanel == .health
        currentPanel = panel
        if panel != .list || leavingHealth {
            selectedItemID = nil
        }
        if panel == .addNew {
            resetNewItem()
            newType = typeFilter ?? .login
        }
    }

    // MARK: - Category Management

    func addCategory() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let key = trimmed.lowercased().replacingOccurrences(of: " ", with: "_")
        guard !categories.contains(where: { $0.key == key }) else { return }

        let category = VaultCategory(key: key, label: trimmed, color: newTagColor)
        categories.append(category)
        newTagName = ""
        newTagColor = VaultCategory.availableColors[0]
    }

    func removeCategory(_ key: String) {
        guard !categoryHasItems(key) else { return }
        categories.removeAll { $0.key == key }
        if activeCategory == key {
            activeCategory = "all"
        }
    }

    func updateCategory(key: String, newLabel: String, newColor: String) {
        guard let idx = categories.firstIndex(where: { $0.key == key }) else { return }
        categories[idx].label = newLabel
        categories[idx].color = newColor
    }

    func categoryHasItems(_ key: String) -> Bool {
        activeItems.contains { $0.category == key }
    }

    func categoryFor(key: String) -> VaultCategory? {
        categories.first { $0.key == key }
    }

    func deleteItem(_ id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].deletedAt = Date()
        }
        if selectedItemID == id {
            selectedItemID = nil
        }
    }

    func restoreItem(_ id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].deletedAt = nil
        }
    }

    func permanentlyDeleteItem(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func emptyTrash() {
        items.removeAll { $0.deletedAt != nil }
    }

    func purgeExpiredTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        items.removeAll { item in
            if let deletedAt = item.deletedAt, deletedAt < cutoff { return true }
            return false
        }
    }

    // MARK: - Edit Item

    func startEditing(_ item: VaultItem) {
        editName = item.name
        editUrl = item.url ?? ""
        editUsername = item.username ?? ""
        editPassword = item.password ?? ""
        editCategory = item.category
        editCardType = item.cardType ?? ""
        editCardHolder = item.cardHolder ?? ""
        editCardNumber = item.cardNumber ?? ""
        editExpiry = item.expiry ?? ""
        editCvv = item.cvv ?? ""
        editCardNotes = item.cardNotes ?? ""
        editNoteText = item.noteText ?? ""
        editTotpSecret = item.totpSecret ?? ""
        editLoginNotes = item.loginNotes ?? ""
        showEditPassword = false
        isEditingItem = true
    }

    func saveEditedItem() {
        guard let id = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }

        items[idx].name = editName
        items[idx].category = editCategory
        items[idx].modifiedAt = Date()

        switch items[idx].type {
        case .login:
            // Track password history if password changed
            if let oldPassword = items[idx].password,
               !oldPassword.isEmpty,
               editPassword != oldPassword {
                let entry = PasswordHistoryEntry(password: oldPassword)
                var history = items[idx].previousPasswords ?? []
                history.insert(entry, at: 0)
                if history.count > 20 { history = Array(history.prefix(20)) }
                items[idx].previousPasswords = history
            }
            items[idx].url = editUrl
            items[idx].username = editUsername.isEmpty ? nil : editUsername
            items[idx].password = editPassword.isEmpty ? nil : editPassword
            items[idx].totpSecret = TOTPService.extractSecret(from: editTotpSecret)
            items[idx].loginNotes = editLoginNotes.isEmpty ? nil : editLoginNotes
        case .card:
            items[idx].cardType = editCardType.isEmpty ? nil : editCardType
            items[idx].cardHolder = editCardHolder
            items[idx].cardNumber = editCardNumber
            items[idx].expiry = editExpiry
            items[idx].cvv = editCvv
            items[idx].cardNotes = editCardNotes.isEmpty ? nil : editCardNotes
        case .note:
            items[idx].noteText = editNoteText
        }

        isEditingItem = false
    }

    func cancelEditing() {
        isEditingItem = false
    }

    // MARK: - Edit Re-authentication

    func requestEditWithReauth(_ item: VaultItem) {
        // Non-login items or logins without passwords don't need re-auth
        guard item.type == .login, let pw = item.password, !pw.isEmpty else {
            startEditing(item)
            return
        }

        // Try Touch ID first if enabled
        if settingsViewModel?.biometricEnabled == true,
           BiometricService.shared.isBiometricAvailable {
            BiometricService.shared.authenticate(reason: "Authenticate to edit credentials") { [weak self] success, _ in
                if success {
                    self?.startEditing(item)
                } else {
                    // Fall back to password prompt
                    self?.reauthPendingItem = item
                    self?.reauthPassword = ""
                    self?.reauthError = ""
                    self?.showReauthPrompt = true
                }
            }
        } else {
            // No biometric — show password prompt
            reauthPendingItem = item
            reauthPassword = ""
            reauthError = ""
            showReauthPrompt = true
        }
    }

    func confirmReauth() {
        guard let item = reauthPendingItem else { return }
        let password = reauthPassword
        reauthPassword = ""

        guard !password.isEmpty else {
            reauthError = "Enter your master password"
            return
        }

        isReauthenticating = true
        reauthError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let saltData = try? self.storage.readSalt(),
                  let vaultData = try? self.storage.readEncryptedVaultDataForVerification(),
                  let version = try? self.storage.readVaultVersion() else {
                DispatchQueue.main.async {
                    self.reauthError = "Verification failed"
                    self.isReauthenticating = false
                }
                return
            }

            let secretKey = SecretKeyService.shared.retrieveSecretKey()
            guard let testKey = EncryptionService.deriveKeyStandalone(
                from: password, salt: saltData, version: version, secretKey: secretKey
            ) else {
                DispatchQueue.main.async {
                    self.reauthError = "Verification failed"
                    self.isReauthenticating = false
                }
                return
            }

            let verified: Bool
            if let box = try? AES.GCM.SealedBox(combined: vaultData.primary),
               let _ = try? AES.GCM.open(box, using: testKey) {
                verified = true
            } else if let box = try? AES.GCM.SealedBox(combined: vaultData.fallback),
                      let _ = try? AES.GCM.open(box, using: testKey) {
                verified = true
            } else {
                verified = false
            }

            guard verified else {
                DispatchQueue.main.async {
                    self.reauthError = "Incorrect password"
                    self.isReauthenticating = false
                }
                return
            }

            DispatchQueue.main.async {
                self.isReauthenticating = false
                self.showReauthPrompt = false
                self.reauthPendingItem = nil
                self.startEditing(item)
            }
        }
    }

    func cancelReauth() {
        showReauthPrompt = false
        reauthPassword = ""
        reauthError = ""
        reauthPendingItem = nil
    }

    // MARK: - Card Input Formatting

    static func formatCardNumber(_ input: String) -> String {
        let digits = input.filter(\.isNumber)
        let capped = String(digits.prefix(16))
        var result = ""
        for (i, ch) in capped.enumerated() {
            if i > 0 && i % 4 == 0 { result += " " }
            result.append(ch)
        }
        return result
    }

    static func formatExpiry(_ input: String) -> String {
        let digits = input.filter(\.isNumber)
        let capped = String(digits.prefix(4))
        if capped.count > 2 {
            return String(capped.prefix(2)) + "/" + String(capped.dropFirst(2))
        }
        return capped
    }

    static func formatCVV(_ input: String) -> String {
        String(input.filter(\.isNumber).prefix(3))
    }

    // MARK: - Import

    func startImport() {
        importError = ""
        importPreview = nil
        importProgress = ""
        importCategory = ""

        guard let url = ImportService.shared.showOpenPanel() else { return }

        let ext = url.pathExtension.lowercased()

        if ext == "knox" || ext == "flapsy" {
            showImportPreview = true
            importPreview = ImportService.ImportResult(items: [], format: .knoxBackup)
            importPreview?.format = .knoxBackup
            _pendingImportURL = url
            return
        }

        isImporting = true
        showImportPreview = true
        importProgress = "Reading file\u{2026}"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try ImportService.shared.importFromFile(url) { progress in
                    DispatchQueue.main.async {
                        self?.importProgress = progress
                    }
                }
                DispatchQueue.main.async {
                    self?.isImporting = false
                    self?.importProgress = ""
                    if result.items.isEmpty {
                        self?.importError = "No items found in file"
                    } else {
                        self?.importPreview = result
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isImporting = false
                    self?.importProgress = ""
                    self?.importError = error.localizedDescription
                }
            }
        }
    }

    private var _pendingImportURL: URL?

    func decryptKnoxBackup(password: String) {
        guard let url = _pendingImportURL else {
            importError = "No file selected"
            return
        }

        isImporting = true
        importError = ""
        importProgress = "Decrypting backup\u{2026}"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try ImportService.shared.importFromFile(url, password: password)
                DispatchQueue.main.async {
                    self?.importPreview = result
                    self?.isImporting = false
                    self?.importProgress = ""
                    if result.items.isEmpty {
                        self?.importError = "Backup contains no items"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.importError = error.localizedDescription
                    self?.isImporting = false
                    self?.importProgress = ""
                }
            }
        }
    }

    func confirmImport() {
        guard let preview = importPreview, !preview.items.isEmpty else { return }

        isImporting = true
        importProgress = "Deduplicating\u{2026}"

        let existingItems = items
        let chosenCategory = importCategory

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var incoming = preview.items

            // Apply chosen category if user selected one
            if !chosenCategory.isEmpty {
                for i in incoming.indices {
                    incoming[i].category = chosenCategory
                }
            }

            let deduplicated = ImportService.shared.deduplicateItems(
                incoming: incoming,
                existing: existingItems
            )

            let total = deduplicated.count
            // Batch items to avoid a single massive SwiftUI diff
            let batchSize = 100
            var offset = 0

            while offset < total {
                let end = min(offset + batchSize, total)
                let batch = Array(deduplicated[offset..<end])
                let current = end

                DispatchQueue.main.sync {
                    self?.importProgress = "Importing \(current) of \(total)\u{2026}"
                    self?.items.append(contentsOf: batch)
                }

                offset = end
            }

            DispatchQueue.main.async {
                self?.isImporting = false
                self?.importProgress = ""
                self?.importCategory = ""
                self?.showImportPreview = false
                self?.importPreview = nil
                self?._pendingImportURL = nil
                self?.exportPasswordInput = ""

                self?.settingsViewModel?.showImportSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.settingsViewModel?.showImportSuccess = false
                }
            }
        }
    }

    func cancelImport() {
        showImportPreview = false
        importPreview = nil
        importError = ""
        importProgress = ""
        importCategory = ""
        isImporting = false
        _pendingImportURL = nil
        exportPasswordInput = ""
    }

    // MARK: - Export

    func startExportBackup() {
        showExportSheet = true
        exportError = ""
        exportPasswordInput = ""
        exportPasswordConfirm = ""
        csvExportConfirmed = false
        csvExportMasterPassword = ""
    }

    func exportEncryptedBackup() {
        let pw = exportPasswordInput
        guard !pw.isEmpty else {
            exportError = "Password is required"
            return
        }
        guard pw == exportPasswordConfirm else {
            exportError = "Passwords do not match"
            return
        }
        guard pw.count >= 8 else {
            exportError = "Password must be at least 8 characters"
            return
        }

        guard let url = ExportService.shared.showSavePanel(format: .encryptedBackup) else { return }

        let settings = settingsViewModel?.toVaultSettings() ?? VaultSettings.defaults
        let vaultData = VaultData(items: activeItems, categories: categories, settings: settings)

        isExporting = true
        exportError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ExportService.shared.exportEncryptedBackup(vault: vaultData, password: pw, to: url)
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.showExportSheet = false
                    self?.exportPasswordInput = ""
                    self?.exportPasswordConfirm = ""
                    self?.settingsViewModel?.lastBackupDate = Date()
                    self?.settingsViewModel?.showExportSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.settingsViewModel?.showExportSuccess = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.exportError = error.localizedDescription
                    self?.isExporting = false
                }
            }
        }
    }

    /// Exports vault as CSV after verifying master password via standalone derivation.
    func exportCSV() {
        let pw = csvExportMasterPassword
        guard !pw.isEmpty else {
            exportError = "Enter your master password to confirm"
            return
        }

        isExporting = true
        exportError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let saltData = try? self.storage.readSalt(),
                  let vaultData = try? self.storage.readEncryptedVaultDataForVerification(),
                  let version = try? self.storage.readVaultVersion() else {
                DispatchQueue.main.async {
                    self.exportError = "Could not verify password"
                    self.isExporting = false
                }
                return
            }

            // Use version-aware standalone derivation
            let secretKey = SecretKeyService.shared.retrieveSecretKey()
            guard let testKey = EncryptionService.deriveKeyStandalone(
                from: pw, salt: saltData, version: version, secretKey: secretKey
            ) else {
                DispatchQueue.main.async {
                    self.exportError = "Key derivation failed"
                    self.isExporting = false
                }
                return
            }

            // Trial decryption (try without HMAC first, then with)
            let exportVerified: Bool
            if let box = try? AES.GCM.SealedBox(combined: vaultData.primary),
               let _ = try? AES.GCM.open(box, using: testKey) {
                exportVerified = true
            } else if let box = try? AES.GCM.SealedBox(combined: vaultData.fallback),
                      let _ = try? AES.GCM.open(box, using: testKey) {
                exportVerified = true
            } else {
                exportVerified = false
            }

            guard exportVerified else {
                DispatchQueue.main.async {
                    self.exportError = "Incorrect master password"
                    self.isExporting = false
                }
                return
            }

            DispatchQueue.main.async {
                self.isExporting = false

                guard let url = ExportService.shared.showSavePanel(format: .csv) else { return }

                do {
                    try ExportService.shared.exportCSV(items: self.activeItems, to: url)
                    self.showExportSheet = false
                    self.csvExportMasterPassword = ""
                    self.settingsViewModel?.lastBackupDate = Date()
                    self.settingsViewModel?.showExportSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.settingsViewModel?.showExportSuccess = false
                    }
                } catch {
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    func cancelExport() {
        showExportSheet = false
        exportError = ""
        exportPasswordInput = ""
        exportPasswordConfirm = ""
        csvExportMasterPassword = ""
        csvExportConfirmed = false
    }

    // MARK: - Biometric Unlock

    func attemptBiometricUnlock() {
        guard BiometricService.shared.isBiometricAvailable,
              KeychainService.biometricEnabledFlag else {
            return
        }

        showBiometricPrompt = true
        biometricFailed = false

        // Touch ID prompt via BiometricService, then read key from Keychain
        BiometricService.shared.authenticate(reason: "Unlock your Knox vault") { [weak self] success, error in
            guard let self = self else { return }

            guard success else {
                self.showBiometricPrompt = false
                self.biometricFailed = true
                return
            }

            KeychainService.shared.retrieveDerivedKey { keyData in
                self.showBiometricPrompt = false

                guard let keyData = keyData else {
                    self.biometricFailed = true
                    return
                }

                do {
                    let vaultData = try self.storage.unlockVault(withKeyData: keyData)
                    self.items = vaultData.items
                    self.categories = vaultData.categories
                    self.settingsViewModel?.loadFromVaultSettings(vaultData.settings)
                    self.isUnlocked = true
                    self.currentScreen = .vault
                    self.currentPanel = .list
                    self.showFavoritesOnly = self.settingsViewModel?.defaultFavoritesFilter ?? false
                    self.masterPasswordInput = ""
                    self.lockError = false
                    self.biometricFailed = false
                    self.setupAutoSave()
                } catch {
                    self.biometricFailed = true
                }
            }
        }
    }

    func enableBiometric() {
        guard var keyData = encryption.currentKeyData else {
            logger.error("enableBiometric: no derived key available")
            return
        }
        let stored = KeychainService.shared.storeDerivedKey(keyData)
        keyData.resetBytes(in: 0..<keyData.count)
        if stored {
            settingsViewModel?.biometricEnabled = true
            KeychainService.biometricEnabledFlag = true
            showEnableBiometricPrompt = false
            persistVault()
        } else {
            logger.error("enableBiometric: Keychain store failed")
            settingsViewModel?.biometricEnabled = false
            KeychainService.biometricEnabledFlag = false
        }
    }

    func disableBiometric() {
        KeychainService.shared.deleteDerivedKey()
        settingsViewModel?.biometricEnabled = false
        KeychainService.biometricEnabledFlag = false
        showEnableBiometricPrompt = false
        persistVault()
    }

    func dismissBiometricPrompt() {
        showEnableBiometricPrompt = false
    }

    // MARK: - Change Password

    var changeNewPasswordStrength: Int {
        PasswordStrength.calculate(changeNewPassword)
    }

    func changePassword() {
        let oldPw = changeOldPassword
        let newPw = changeNewPassword
        let confirmPw = changeConfirmPassword
        changeOldPassword = ""
        changeNewPassword = ""
        changeConfirmPassword = ""

        guard !oldPw.isEmpty else {
            changePasswordError = "Enter your current password"
            return
        }
        guard newPw.count >= 12 else {
            changePasswordError = "New password must be at least 12 characters"
            return
        }
        guard PasswordStrength.calculate(newPw) >= PasswordStrength.minimumRequired else {
            changePasswordError = "Password is too weak — use a mix of upper/lowercase, numbers, and symbols"
            return
        }
        guard newPw == confirmPw else {
            changePasswordError = "Passwords do not match"
            return
        }

        isChangingPassword = true
        changePasswordError = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let saltData = try? self.storage.readSalt(),
                  let vaultData = try? self.storage.readEncryptedVaultDataForVerification(),
                  let version = try? self.storage.readVaultVersion() else {
                DispatchQueue.main.async {
                    self.changePasswordError = "Could not verify password"
                    self.isChangingPassword = false
                }
                return
            }

            // Verify old password using version-aware standalone derivation
            let secretKey = SecretKeyService.shared.retrieveSecretKey()
            guard let testKey = EncryptionService.deriveKeyStandalone(
                from: oldPw, salt: saltData, version: version, secretKey: secretKey
            ) else {
                DispatchQueue.main.async {
                    self.changePasswordError = "Key derivation failed"
                    self.isChangingPassword = false
                }
                return
            }

            // Trial decryption (try without HMAC first, then with)
            let changePwVerified: Bool
            if let box = try? AES.GCM.SealedBox(combined: vaultData.primary),
               let _ = try? AES.GCM.open(box, using: testKey) {
                changePwVerified = true
            } else if let box = try? AES.GCM.SealedBox(combined: vaultData.fallback),
                      let _ = try? AES.GCM.open(box, using: testKey) {
                changePwVerified = true
            } else {
                changePwVerified = false
            }

            guard changePwVerified else {
                DispatchQueue.main.async {
                    self.changePasswordError = "Incorrect current password"
                    self.isChangingPassword = false
                }
                return
            }

            // Old password verified — re-encrypt with new password (always v2)
            do {
                let newSalt = self.encryption.generateSalt(byteCount: 32)
                let sk = secretKey ?? SecretKeyService.shared.generateSecretKey()
                if secretKey == nil {
                    SecretKeyService.shared.storeSecretKey(sk)
                }

                guard self.encryption.deriveKeyV2(from: newPw, salt: newSalt, secretKey: sk) != nil else {
                    throw EncryptionError.keyDerivationFailed
                }
                try self.storage.writeSalt(newSalt)

                let settings = self.settingsViewModel?.toVaultSettings() ?? VaultSettings.defaults
                let vault = VaultData(items: self.items, categories: self.categories, settings: settings)
                try self.storage.saveVault(vault)

                // Always invalidate old biometric key on password change.
                // If biometric is enabled, re-store with the new derived key.
                // If disabled, just delete the stale key so re-enabling later
                // won't use an outdated key.
                if self.settingsViewModel?.biometricEnabled == true,
                   var keyData = self.encryption.currentKeyData {
                    KeychainService.shared.storeDerivedKey(keyData)
                    keyData.resetBytes(in: 0..<keyData.count)
                } else {
                    KeychainService.shared.deleteDerivedKey()
                }

                DispatchQueue.main.async {
                    self.isChangingPassword = false
                    self.changePasswordSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.changePasswordSuccess = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.changePasswordError = "Failed to update password: \(error.localizedDescription)"
                    self.isChangingPassword = false
                }
            }
        }
    }

    func resetChangePassword() {
        changeOldPassword = ""
        changeNewPassword = ""
        changeConfirmPassword = ""
        changePasswordError = ""
        changePasswordSuccess = false
        isChangingPassword = false
    }

    // MARK: - Vault Reset

    /// Permanently deletes all vault data and returns to the setup screen.
    func resetVault() {
        isResetting = true

        // Cancel auto-save so it doesn't fire during teardown
        autoSaveDebounce?.cancel()
        autoSaveDebounce = nil

        // Delete all persistent data (vault file, salt, keychain keys, biometric flag)
        storage.deleteVaultFiles()

        // Clear all in-memory vault state
        items = []
        categories = []
        selectedItemID = nil
        searchText = ""
        activeCategory = "all"
        typeFilter = nil
        showFavoritesOnly = false
        isUnlocked = false
        masterPasswordInput = ""
        lockError = false
        lockErrorMessage = ""
        failedAttempts = 0
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        isLockedOut = false
        lockoutRemainingSeconds = 0

        // Reset settings to defaults
        settingsViewModel?.resetToDefaults()

        // Reset confirmation state
        showResetConfirmation = false
        resetConfirmText = ""
        isResetting = false

        // Navigate to fresh setup screen
        isOnboarding = true
        onboardingPasswordCreated = false
        currentPanel = .list
        currentScreen = .setup
    }

    func cancelReset() {
        showResetConfirmation = false
        resetConfirmText = ""
    }

    // MARK: - Start Fresh (from Lock Screen)

    /// Backs up the vault, deletes all vault data, and navigates to setup.
    func startFresh() {
        autoSaveDebounce?.cancel()
        autoSaveDebounce = nil

        // Backup vault then delete (keeps .bak)
        storage.deleteVaultFilesKeepingBackup()

        // Clear in-memory state
        items = []
        categories = []
        selectedItemID = nil
        searchText = ""
        activeCategory = "all"
        typeFilter = nil
        showFavoritesOnly = false
        isUnlocked = false
        masterPasswordInput = ""
        lockError = false
        lockErrorMessage = ""
        failedAttempts = 0
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        isLockedOut = false
        lockoutRemainingSeconds = 0
        needsSecretKeyRecovery = false
        secretKeyRecoveryInput = ""
        secretKeyRecoveryError = ""

        settingsViewModel?.resetToDefaults()

        // Reset Start Fresh state
        showStartFreshConfirmation = false
        startFreshConfirmText = ""

        // Navigate to setup
        isOnboarding = true
        onboardingPasswordCreated = false
        currentPanel = .list
        currentScreen = .setup
    }

    func cancelStartFresh() {
        showStartFreshConfirmation = false
        startFreshConfirmText = ""
    }
}

// MARK: - EncryptionError Equatable

extension EncryptionError: Equatable {
    static func == (lhs: EncryptionError, rhs: EncryptionError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
