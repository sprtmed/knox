# KNOX Password Manager

**A no-nonsense password manager for Mac.**

KNOX lives in your menu bar. It stores your passwords locally, encrypted with the same cryptography used by intelligence agencies. No cloud. No subscriptions. No bloat. Just your passwords, locked down tight.

We built KNOX because we were fed up. Every password manager out there keeps bolting on features nobody asked for — browser extensions that break, cloud sync that leaks, family plans, travel mode, dark web monitoring, "security scores." Meanwhile, the core job — *storing passwords securely* — gets buried under feature creep.

KNOX does one thing and does it well.

---

## Download

Grab the latest release from the [Releases page](https://github.com/sprtmed/Knox-Password-Manager/releases/latest). Open the DMG, drag Knox to Applications, and launch. Fully notarized — no Gatekeeper warnings.

---

## Features

- **Menu bar app** — Click the icon or press `Cmd+Shift+P` to open. No dock icon, no window clutter
- **Logins, cards & notes** — Store passwords, credit/debit cards (Visa, Mastercard, Amex, Discover, UnionPay), and secure notes — all encrypted in one vault
- **TOTP / 2FA** — Add a TOTP secret or `otpauth://` URI to any login and Knox generates live 6-digit codes with a countdown timer. No separate authenticator app needed
- **Fuzzy search** — Search field auto-focuses on open (`Cmd+K` shortcut). Fuzzy matching with score-ranked results and character highlighting
- **Password generator** — Three modes: random (length 12–50, numbers/symbols toggles), memorable passphrase (EFF wordlist, 2–8 words, custom separator), and PIN (4–12 digits). Real-time strength meter on all modes
- **Quick copy** — Copy a password straight from the vault list without opening the detail view
- **Open URL + copy password** — One click to launch the site in your browser and copy the password to your clipboard
- **Categories & favorites** — Organize your vault with custom color-coded categories and a favorites filter
- **Vault health** — Security score with detection of weak, reused, and duplicate passwords. Edit and fix items inline without leaving the health panel
- **Breach detection** — Checks your passwords against Have I Been Pwned using k-anonymity (only a 5-character SHA-1 prefix leaves your machine — your passwords never do)
- **Trash** — Deleted items go to a 30-day trash. Restore mistakes or empty it manually
- **Markdown notes** — Secure notes render markdown (bold, italic, code, links) with a raw/rich toggle
- **Touch ID** — Unlock with your fingerprint
- **Auto-lock** — Locks automatically after inactivity, sleep, or screen lock. Configurable timer (1–30 minutes)
- **Clipboard auto-clear** — Copied passwords are marked as concealed and automatically cleared after a configurable timer (5–120 seconds)
- **Import** — Bring your passwords from 1Password, Bitwarden, Chrome, or any generic CSV. Knox encrypted backups (`.knox`) too
- **Export** — Encrypted `.knox` backup or plain CSV. Backup reminder if you haven't exported in 30+ days
- **Dark & light mode** — Follows your preference
- **Menu bar icon picker** — Choose your preferred icon style from the settings
- **Window pinning** — Pin the Knox popover so it stays open when you click elsewhere
- **Password history** — Tracks the last 20 passwords for each login item with timestamps, so you can roll back if needed
- **Edit re-authentication** — Requires master password or Touch ID before editing login credentials, preventing unauthorized changes
- **Vault overwrite protection** — Automatic backups on every save, Keychain recovery, and "Start Fresh" safety net
- **Secret Key & Emergency Kit** — A 128-bit secret key is generated alongside your master password. Knox displays it as a formatted base32 "Emergency Kit" after vault creation so you can store it safely
- **Secret Key recovery** — If your Keychain is lost or you move to a new Mac, enter your base32 secret key on the lock screen to regain access
- **Secure Enclave** — On Apple Silicon, your secret key is wrapped by a hardware-bound key inside the Secure Enclave. Even root cannot extract it. Falls back to Keychain on Intel Macs
- **Guided onboarding** — A step-by-step first-launch wizard walks you through creating a master password, setting up Touch ID, and importing existing data
- **Update checker** — Optionally checks GitHub releases on launch and shows a badge when a new version is available
- **Completely free** — No trials, no tiers, no subscriptions. Ever.

---

## Security

This is a password manager, so security isn't a feature — it's the foundation. Here's exactly what KNOX uses:

| Layer | Implementation |
|-------|---------------|
| **Encryption** | AES-256-GCM (CryptoKit) |
| **Key derivation** | Argon2id — 128 MB memory, 3 iterations, 4 parallel lanes |
| **Secret Key** | 128-bit random key stored in macOS Keychain, mixed via HKDF-SHA256 |
| **Secure Enclave** | On Apple Silicon, the Secret Key is wrapped by a hardware-bound P-256 key in the Secure Enclave. Even root cannot extract it. Falls back to Keychain on Intel |
| **Key memory** | Pinned to RAM (`mlock`), zeroed on lock (`resetBytes`) |
| **Anti-debug** | `ptrace(PT_DENY_ATTACH)` + `sysctl` detection in release builds |
| **File permissions** | `0600` (owner read/write only) on all vault files |
| **Vault integrity** | HMAC-SHA256 over entire vault file, verified on every unlock |
| **Salt integrity** | SHA-256 checksum with redundant copy in vault header |
| **Edit re-auth** | Master password or Touch ID required before editing credentials |
| **Password history** | Last 20 passwords per item with timestamps, encrypted in vault |
| **Brute-force protection** | Exponential backoff (2s, 4s, 8s, 16s, 30s cap), persisted across restarts |
| **Clipboard** | Marked as concealed (`NSPasteboard.ConcealedType`) + auto-clear timer |
| **Password requirements** | 12-character minimum with real-time strength scoring |
| **Storage** | Local only — `~/Library/Application Support/Knox/` |
| **Vault backup** | Rolling backup (`vault.enc.bak`) created automatically on every save |
| **Network** | Outbound only — a single GitHub API call to check for updates. No telemetry, no analytics, no cloud sync |
| **Biometrics** | Touch ID via `LAContext` with `.biometryCurrentSet` (invalidates on enrollment change) |
| **Runtime** | Hardened Runtime enabled |

### How your vault is encrypted

```
Master Password + Salt (32 bytes)
        |
        v
    Argon2id (128 MB, 3 iterations, 4 lanes)
        |
        v
  Intermediate Key + Secret Key (128-bit, from Keychain)
        |
        v
    HKDF-SHA256 ("com.knox.vault-key")
        |
        v
    256-bit AES Key
        |
        v
    AES-256-GCM encrypt/decrypt
```

Your vault file (`vault.enc`) contains a 40-byte header (`FLPV` magic + version + embedded salt) followed by the AES-256-GCM ciphertext and a 32-byte HMAC-SHA256 integrity tag. The HMAC is computed over the entire file (header + ciphertext) using a separate key derived via HKDF from the vault key. On every unlock, KNOX verifies the HMAC before trusting the data — any tampering or corruption is detected immediately.

Even if someone steals the file, they need both your master password AND the 128-bit secret key to decrypt it. Brute-forcing that combination is computationally infeasible.

### What KNOX can't protect against

We believe in transparency. KNOX cannot defend against:

- Malware running as your user (this applies to every password manager)
- A compromised operating system or kernel
- Someone with physical access to your unlocked Mac

These are OS-level threats, not application-level ones.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (to build from source)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
# Clone the repo
git clone https://github.com/sprtmed/Knox-Password-Manager.git
cd Knox-Password-Manager

# Generate Xcode project
xcodegen generate

# Build and run
open Knox.xcodeproj
# Press Cmd+R in Xcode
```

After building, KNOX appears in your menu bar — look for the lock icon in the top-right of your screen.

---

## Vault file format

For the security-curious:

```
Offset  Size    Content
0       4       Magic bytes: "FLPV"
4       4       Version: UInt32 big-endian (2 = Argon2id)
8       32      Salt (redundant backup copy)
40      ...     AES-256-GCM ciphertext (nonce + encrypted JSON + auth tag)
EOF-32   32     HMAC-SHA256 integrity tag over bytes [0..EOF-32]
```

Salt is stored separately in `salt.dat` (32 bytes + SHA-256 checksum = 64 bytes) with a fallback to the embedded copy in the vault header. The HMAC tag uses a separate key derived via `HKDF-SHA256(vaultKey, info: "com.knox.vault-hmac")`.

---

## Why "KNOX"

Fort Knox. Where the gold is kept. Seemed fitting for a vault.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
