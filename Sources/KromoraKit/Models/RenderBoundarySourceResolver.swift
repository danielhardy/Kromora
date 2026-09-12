import Foundation

/// Resolves a package-relative source only at the render boundary.
///
/// Relative paths are package bookkeeping, not identity. Callers should keep the relative string
/// in package records and invoke this immediately before creating the URL-backed render source.
enum RenderBoundarySourceResolver {
    enum ResolutionError: Error, Equatable {
        case absolutePathNotAllowed
        case escapesPackage
    }

    static func resolve(
        packageRelativePath: String,
        packageRoot: URL
    ) throws -> URL {
        guard !packageRelativePath.isEmpty,
              !packageRelativePath.hasPrefix("/"),
              !packageRelativePath.hasPrefix("~") else {
            throw ResolutionError.absolutePathNotAllowed
        }

        let root = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appendingPathComponent(packageRelativePath, isDirectory: false)
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw ResolutionError.escapesPackage
        }
        return candidate
    }
}
