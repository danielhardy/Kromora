import SystemConfiguration

/// The user-visible computer name, read from the local dynamic store.
///
/// System hostname APIs can trigger reverse DNS and block for seconds on some networks, so none are
/// used here.
enum DeviceName {
    static func current() -> String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
            return name
        }
        // `ProcessInfo.hostName` can also block on a network lookup, so fall back to a literal.
        return "This Mac"
    }
}
