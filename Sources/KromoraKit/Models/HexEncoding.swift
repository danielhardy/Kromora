extension Sequence where Element == UInt8 {
    /// Lowercase hexadecimal encoding with no separators, e.g. a digest or checksum string.
    var hexString: String {
        let digits = Array("0123456789abcdef".utf8)
        let bytes = Array(self)
        return String(unsafeUninitializedCapacity: bytes.count * 2) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index * 2] = digits[Int(byte >> 4)]
                buffer[index * 2 + 1] = digits[Int(byte & 0x0f)]
            }
            return bytes.count * 2
        }
    }
}
