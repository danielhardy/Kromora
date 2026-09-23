import Foundation

/// A validated path whose spelling is relative to a portable package root.
///
/// Validation is deliberately performed both lexically and against the current filesystem. The
/// latter rejects a symlink in any component when it resolves outside the package root. Callers
/// must still keep the returned URL operation close to the subsequent file operation: this is a
/// containment check, not an atomic capability, so a hostile concurrent rename can only be
/// prevented by descriptor-relative OS primitives at a higher boundary.
struct PackagePath: Hashable, Sendable {
    let relativePath: String

    init(_ relativePath: String) throws {
        guard Self.isLexicallySafe(relativePath) else {
            throw PackagePathError.invalid(relativePath)
        }
        self.relativePath = relativePath
    }

    func url(in packageRoot: URL) throws -> URL {
        let root = packageRoot.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        var prefix = resolvedRoot
        for component in relativePath.split(separator: "/") {
            prefix = prefix.appendingPathComponent(String(component), isDirectory: false)
            let resolvedPrefix = prefix.resolvingSymlinksInPath().standardizedFileURL
            guard Self.isContained(resolvedPrefix, in: resolvedRoot) else {
                throw PackagePathError.escapesRoot(relativePath)
            }
            prefix = resolvedPrefix
        }
        return candidate
    }

    static func isLexicallySafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let prefix = root.path == "/" ? "/" : (root.path.hasSuffix("/") ? root.path : root.path + "/")
        return candidate.path == root.path || candidate.path.hasPrefix(prefix)
    }
}

enum PackagePathError: Error, Equatable {
    case invalid(String)
    case escapesRoot(String)
}
