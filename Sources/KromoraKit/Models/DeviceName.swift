import SystemConfiguration

/// The user-visible computer name, read from the local dynamic store.
///
/// `Host.current().localizedName` and `ProcessInfo.hostName` can trigger reverse DNS and block for
/// seconds on some networks, so neither is used here.
enum DeviceName {
    static func current() -> String {
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
            return name
        }
        // `ProcessInfo.hostName` can also block on a network lookup, so fall back to a literal.
        return "This Mac"
    }
}
