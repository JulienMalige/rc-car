import CommonCrypto

/// One 16-byte block of AES-128 in ECB mode, no padding: what the QCAR cars speak.
public enum AES128 {
    public static func encrypt(_ block: [UInt8], key: [UInt8]) -> [UInt8]? {
        crypt(CCOperation(kCCEncrypt), block, key)
    }

    public static func decrypt(_ block: [UInt8], key: [UInt8]) -> [UInt8]? {
        crypt(CCOperation(kCCDecrypt), block, key)
    }

    private static func crypt(_ operation: CCOperation, _ input: [UInt8], _ key: [UInt8]) -> [UInt8]? {
        guard input.count == kCCBlockSizeAES128, key.count == kCCKeySizeAES128 else { return nil }
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var moved = 0
        let status = CCCrypt(
            operation,
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            input, input.count,
            &output, capacity,
            &moved
        )
        guard status == CCCryptorStatus(kCCSuccess), moved == input.count else { return nil }
        return Array(output.prefix(moved))
    }
}
