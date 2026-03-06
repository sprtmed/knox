# Knox — Future Improvements

Items to consider implementing. All aligned with local-only, no-cloud, no-extension philosophy.

## Security

- [ ] **Breach Detection (HIBP k-Anonymity)** — Check passwords against Have I Been Pwned using k-anonymity API (sends only first 5 chars of SHA-1 prefix). Upgrade Health panel from weak/reused to weak/reused/compromised. Optional, user-togglable in settings.

- [ ] **Password Change Re-authentication** — Require master password re-entry (or Touch ID) before allowing password change. Prevents unauthorized change if vault is left unlocked.

- [ ] **Password History per Item** — Track `previousPasswords: [(password, changedAt)]` on VaultItem. Lets user recover old credential if a site update goes wrong. Already encrypted in vault.

- [ ] **Vault Integrity HMAC** — Add HMAC-SHA256 tag (32 bytes) over full vault file using a key derived from vault key. Catches corruption before decryption.

## Features

- [ ] **System Appearance Sync** — Add "Match System" theme option that observes `NSApp.effectiveAppearance` and auto-switches dark/light.

- [ ] **Configurable Global Hotkey** — Let user pick their own hotkey instead of hardcoded Cmd+Shift+P. Store modifier + keyCode in VaultSettings.

- [ ] **Timestamped Backups** — Instead of single rolling `vault.enc.bak`, create timestamped backups (e.g., `vault.enc.2026-03-06.bak`) with configurable retention count (keep last N).

- [ ] **Custom Fields on Items** — Add `customFields: [(label, value, isSensitive)]` array to VaultItem for security questions, PINs, recovery codes, etc.

- [ ] **Wire `lastBackupDate`** — The field exists in VaultSettings but is never set. Set it when ExportService completes a backup. Show "Last backup: X days ago" in Settings.
