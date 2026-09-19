import AppKit
import Combine
import Foundation
import os

/// Coordinates manual and daily GitHub Releases checks and the in-app update presentation.
@MainActor
public final class UpdateCoordinator: ObservableObject {
    public enum Phase: Equatable {
        case checking
        case upToDate
        case available(KromoraRelease)
        case skipped(KromoraRelease)
        case downloading(KromoraRelease)
        case installing(KromoraRelease)
        case failed(String)
    }

    public typealias Fetch = @Sendable () async throws -> KromoraRelease
    public typealias Install = @Sendable (KromoraRelease) async throws -> URL
    public typealias OpenReleasePage = @MainActor @Sendable (URL) -> Bool

    @Published public private(set) var phase: Phase?
    @Published public var isSheetPresented = false
    public let canInstallInPlace: Bool
    public let currentVersion: AppVersion?

    private let fetch: Fetch
    private let install: Install
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let openPage: OpenReleasePage
    private var task: Task<Void, Never>?

    public static let automaticInterval: TimeInterval = 24 * 60 * 60
    public nonisolated static let log = Logger(subsystem: "com.kromora.photo", category: "updates")

    public init(
        currentVersion: AppVersion? = AppVersion.current,
        canInstallInPlace: Bool = KromoraUpdateInstaller.canInstallInPlace,
        defaults: UserDefaults = .standard,
        fetch: @escaping Fetch = { try await KromoraReleaseFeed.fetchLatest() },
        install: @escaping Install = { try await KromoraUpdateInstaller.install($0) },
        now: @escaping @Sendable () -> Date = Date.init,
        openPage: @escaping OpenReleasePage = { NSWorkspace.shared.open($0) }
    ) {
        self.currentVersion = currentVersion
        self.canInstallInPlace = canInstallInPlace
        self.defaults = defaults
        self.fetch = fetch
        self.install = install
        self.now = now
        self.openPage = openPage
    }

    public var checksAutomatically: Bool {
        get { defaults.object(forKey: "Kromora.settings.automaticUpdateChecks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "Kromora.settings.automaticUpdateChecks") }
    }

    public var lastCheck: Date? {
        get { defaults.object(forKey: "Kromora.updates.lastCheck") as? Date }
        set { defaults.set(newValue, forKey: "Kromora.updates.lastCheck") }
    }

    public var skippedVersion: AppVersion? {
        get { defaults.string(forKey: "Kromora.updates.skippedVersion").flatMap(AppVersion.init) }
        set { defaults.set(newValue?.description, forKey: "Kromora.updates.skippedVersion") }
    }

    public var isAutomaticCheckDue: Bool {
        guard checksAutomatically, currentVersion != nil else { return false }
        guard let lastCheck else { return true }
        return now().timeIntervalSince(lastCheck) >= Self.automaticInterval
    }

    public func checkAutomaticallyIfDue() {
        guard isAutomaticCheckDue else { return }
        check(userInitiated: false)
    }

    public func checkNow() {
        check(userInitiated: true)
    }

    public func isNewer(_ release: KromoraRelease) -> Bool {
        guard let currentVersion else { return true }
        return release.version > currentVersion
    }

    public func skip(_ release: KromoraRelease) {
        skippedVersion = release.version
        dismiss()
    }

    public func remindLater() { dismiss() }

    public func openReleasePage(_ release: KromoraRelease) {
        _ = openPage(release.pageURL)
        dismiss()
    }

    public func installAndRelaunch(_ release: KromoraRelease) {
        guard canInstallInPlace else {
            openReleasePage(release)
            return
        }
        Self.log.info("install started for \(release.version.description)")
        phase = .downloading(release)
        let install = self.install
        task?.cancel()
        task = Task { @MainActor [weak self] in
            do {
                let installed = try await install(release)
                guard let self, !Task.isCancelled else { return }
                Self.log.info("install landed at \(installed.path)")
                self.phase = .installing(release)
                self.isSheetPresented = false
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                KromoraUpdateInstaller.relaunch(installed)
            } catch {
                guard let self, !Task.isCancelled else { return }
                Self.log.error("install failed: \(error.localizedDescription)")
                self.phase = .failed(error.localizedDescription)
                self.isSheetPresented = true
            }
        }
    }

    public func dismiss() {
        isSheetPresented = false
        phase = nil
    }

    private func check(userInitiated: Bool) {
        if case .downloading = phase { return }
        if case .installing = phase { return }
        task?.cancel()
        if userInitiated {
            phase = .checking
            isSheetPresented = true
        }
        let fetch = self.fetch
        Self.log.info("update check started (manual: \(userInitiated), running: \(self.currentVersion?.description ?? "dev"))")
        task = Task { @MainActor [weak self] in
            let result: Result<KromoraRelease, Error>
            do { result = .success(try await fetch()) }
            catch { result = .failure(error) }
            guard let self, !Task.isCancelled else { return }
            self.lastCheck = self.now()
            switch result {
            case .failure(let error):
                Self.log.error("update check failed: \(error.localizedDescription)")
                self.phase = userInitiated ? .failed(error.localizedDescription) : nil
                if !userInitiated { self.isSheetPresented = false }
            case .success(let release):
                guard self.isNewer(release) else {
                    Self.log.info("up to date (latest \(release.version.description))")
                    self.phase = userInitiated ? .upToDate : nil
                    if !userInitiated { self.isSheetPresented = false }
                    return
                }
                if !userInitiated, release.version == self.skippedVersion {
                    Self.log.info("update \(release.version.description) is skipped")
                    self.phase = nil
                    self.isSheetPresented = false
                } else if userInitiated, release.version == self.skippedVersion {
                    Self.log.info("manual check found skipped update \(release.version.description)")
                    self.phase = .skipped(release)
                    self.isSheetPresented = true
                } else {
                    Self.log.info("update available: \(release.version.description)")
                    self.phase = .available(release)
                    self.isSheetPresented = true
                }
            }
        }
    }
}
