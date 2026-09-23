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
        guard !packageRelativePath.hasPrefix("~") else {
            throw ResolutionError.absolutePathNotAllowed
        }
        do {
            return try PackagePath(packageRelativePath).url(in: packageRoot)
        } catch PackagePathError.invalid(let path) where path.hasPrefix("/") {
            throw ResolutionError.absolutePathNotAllowed
        } catch {
            throw ResolutionError.escapesPackage
        }
    }
}
