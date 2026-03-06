import Foundation
import CryptoKit

enum TOTPService {
    /// Generates a TOTP code per RFC 6238 / RFC 4226.
    /// - Parameters:
    ///   - secret: Base32-encoded shared secret
    ///   - time: Current time (defaults to now)
    ///   - period: Time step in seconds (default 30)
    ///   - digits: Number of output digits (default 6)
    /// - Returns: Tuple of (code string, seconds remaining in current period), or nil if secret is invalid
    static func generate(secret: String, time: Date = Date(), period: Int = 30, digits: Int = 6) -> (code: String, remaining: Int)? {
        guard let keyData = base32Decode(secret) else { return nil }
        let key = SymmetricKey(data: keyData)

        let timeInterval = Int(time.timeIntervalSince1970)
        let counter = UInt64(timeInterval / period)
        let remaining = period - (timeInterval % period)

        // Counter as big-endian 8 bytes
        var counterBE = counter.bigEndian
        let counterData = Data(bytes: &counterBE, count: 8)

        // HMAC-SHA1 (mandated by RFC 6238 for interoperability)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hash = Array(hmac)

        // Dynamic truncation (RFC 4226 §5.4)
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let truncated = (Int(hash[offset]) & 0x7f) << 24
            | (Int(hash[offset + 1]) & 0xff) << 16
            | (Int(hash[offset + 2]) & 0xff) << 8
            | (Int(hash[offset + 3]) & 0xff)

        let mod = Int(pow(10, Double(digits)))
        let otp = truncated % mod
        let code = String(format: "%0\(digits)d", otp)

        return (code, remaining)
    }

    /// Validates a base32-encoded TOTP secret.
    static func isValidSecret(_ secret: String) -> Bool {
        guard !secret.isEmpty else { return false }
        return base32Decode(secret) != nil
    }

    /// Extracts the secret from an otpauth:// URI.
    /// e.g. otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
    static func extractSecret(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let components = URLComponents(string: trimmed),
                  let secretParam = components.queryItems?.first(where: { $0.name == "secret" })?.value else {
                return nil
            }
            return secretParam.uppercased()
        }

        // Plain base32 secret — strip spaces/dashes and validate
        let cleaned = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        return isValidSecret(cleaned) ? cleaned : nil
    }

    // MARK: - Base32 Decoding (RFC 4648)

    private static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    private static func base32Decode(_ input: String) -> Data? {
        let cleaned = input
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")

        guard !cleaned.isEmpty else { return nil }

        var bits = 0
        var accumulator = 0
        var output = Data()

        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            let value = base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            accumulator = (accumulator << 5) | value
            bits += 5

            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 0xff))
            }
        }

        return output.isEmpty ? nil : output
    }
}
