import AppKit
import Foundation

/// Owns process-level notifications and package maintenance admission. Feature coordinators expose
/// value-oriented refresh hooks; the shell owns observer tokens and their cancellation order.
@MainActor
final class ApplicationShellCoordinator {
    private let mediaNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private let scheduler: ImageWorkScheduler
    let maintenance: PortablePackageMaintenance
    private let packageURL: URL?
    private let packageLease: PortablePackageLease?
    private let idleDelay: Duration
    private let maintenanceJobID = ImageWorkScheduler.JobID("portable-package-maintenance")
    private var mediaObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var mediaRefreshTask: Task<Void, Never>?
    private var maintenanceTriggerTask: Task<Void, Never>?
    private var isShuttingDown = false

    var onMediaChanged: (@MainActor () -> Void)?
    var onApplicationActivated: (@MainActor () -> Void)?

    init(
        mediaNotificationCenter: NotificationCenter,
        applicationNotificationCenter: NotificationCenter,
        scheduler: ImageWorkScheduler,
        maintenance: PortablePackageMaintenance,
        packageURL: URL?,
        packageLease: PortablePackageLease?,
        idleDelay: Duration
    ) {
        self.mediaNotificationCenter = mediaNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        self.scheduler = scheduler
        self.maintenance = maintenance
        self.packageURL = packageURL
        self.packageLease = packageLease
        self.idleDelay = idleDelay
    }

    func start() {
        guard mediaObservers.isEmpty, !isShuttingDown else { return }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mediaObservers.append(
                mediaNotificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleMediaRefresh() }
                }
            )
        }
        applicationObservers.append(
            applicationNotificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.scheduleMediaRefresh()
                    self.scheduleMaintenance()
                    self.onApplicationActivated?()
                }
            }
        )
    }

    private func scheduleMediaRefresh() {
        guard !isShuttingDown else { return }
        mediaRefreshTask?.cancel()
        mediaRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled, let self, !self.isShuttingDown else { return }
            self.onMediaChanged?()
        }
    }

    func scheduleMaintenance() {
        guard !isShuttingDown,
            let packageURL,
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("manifest.json").path
            ),
            !scheduler.contains(maintenanceJobID)
        else { return }
        maintenanceTriggerTask?.cancel()
        maintenanceTriggerTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.idleDelay) } catch { return }
            guard !Task.isCancelled, !self.isShuttingDown,
                let packageURL = self.packageURL,
                !self.scheduler.contains(self.maintenanceJobID)
            else { return }
            _ = self.maintenance.enqueue(
                packageURL: packageURL, lease: self.packageLease, id: self.maintenanceJobID
            )
        }
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        mediaRefreshTask?.cancel()
        maintenanceTriggerTask?.cancel()
        let tasks = [mediaRefreshTask, maintenanceTriggerTask]
        mediaRefreshTask = nil
        maintenanceTriggerTask = nil
        for observer in mediaObservers { mediaNotificationCenter.removeObserver(observer) }
        for observer in applicationObservers { applicationNotificationCenter.removeObserver(observer) }
        mediaObservers.removeAll()
        applicationObservers.removeAll()
        maintenance.shutdown()
        for task in tasks { await task?.value }
    }
}
