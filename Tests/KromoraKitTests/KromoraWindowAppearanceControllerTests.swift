import AppKit
import XCTest
@testable import KromoraKit

@MainActor
final class KromoraWindowAppearanceControllerTests: XCTestCase {

    private func makeSettings(mode: KromoraAppearanceMode = .system) -> KromoraSettings {
        let suite = "KromoraWindowAppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = KromoraSettings(preferences: defaults)
        settings.appearanceMode = mode
        return settings
    }

    func testPreferenceMapsToSystemOrDarkMode() {
        XCTAssertEqual(KromoraAppearanceMode(alwaysDarkMode: false), .system)
        XCTAssertEqual(KromoraAppearanceMode(alwaysDarkMode: true), .dark)
    }

    func testLightModeForcesAquaOnApplicationAndWindows() {
        let settings = makeSettings()
        var applied: [NSAppearance.Name?] = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: true)
        let controller = KromoraWindowAppearanceController(
            settings: settings, windowProvider: { [window] }, applicationAppearanceApplier: { applied.append($0?.name) })
        controller.start()

        settings.appearanceMode = .light
        XCTAssertEqual(window.appearance?.name, .aqua)
        settings.appearanceMode = .dark
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        settings.appearanceMode = .system
        XCTAssertNil(window.appearance)
        XCTAssertEqual(applied, [nil, .aqua, .darkAqua, nil])
        controller.stop()
    }

    func testThemeColorsResolveUnderForcedModes() {
        let light = KromoraTheme.resolvedCanvasBackgroundColor(for: KromoraAppearanceMode.light.appearance)
        let dark = KromoraTheme.resolvedCanvasBackgroundColor(for: KromoraAppearanceMode.dark.appearance)
        XCTAssertGreaterThan(light.redComponent, 0.8)
        XCTAssertLessThan(dark.redComponent, 0.2)
    }

    func testModeTitlesAndRawValuesAreStable() {
        XCTAssertEqual(KromoraAppearanceMode.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(KromoraAppearanceMode.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    func testWindowOverridePropagatesAndClearsForMacOSFollowingMode() {
        let settings = makeSettings()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = KromoraWindowAppearanceController(settings: settings)

        controller.applyCurrentAppearance(to: [window])
        XCTAssertNil(window.appearance)

        settings.appearanceMode = .dark
        controller.applyCurrentAppearance(to: [window])
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        settings.appearanceMode = .system
        controller.applyCurrentAppearance(to: [window])
        XCTAssertNil(window.appearance)
        controller.stop()
    }

    func testStartedControllerUpdatesExistingWindowImmediatelyAfterPreferenceChange() {
        let settings = makeSettings()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = KromoraWindowAppearanceController(
            settings: settings,
            windowProvider: { [window] }
        )
        controller.start()

        settings.appearanceMode = .dark
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        settings.appearanceMode = .system
        XCTAssertNil(window.appearance)
        controller.stop()
    }

    func testStartedControllerAppliesAppearanceToNativeApplicationChrome() {
        let settings = makeSettings()
        var appliedAppearanceNames: [NSAppearance.Name?] = []
        let controller = KromoraWindowAppearanceController(
            settings: settings,
            windowProvider: { [] },
            applicationAppearanceApplier: { appearance in
                appliedAppearanceNames.append(appearance?.name)
            }
        )
        controller.start()

        settings.appearanceMode = .dark
        settings.appearanceMode = .system

        XCTAssertEqual(appliedAppearanceNames, [nil, .darkAqua, nil])
        controller.stop()
    }

    func testAQueuedWindowRefreshCannotRestoreDarkModeAfterTurningItOff() async {
        let settings = makeSettings()
        var appliedAppearanceNames: [NSAppearance.Name?] = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = KromoraWindowAppearanceController(
            settings: settings,
            windowProvider: { [window] },
            applicationAppearanceApplier: { appearance in
                appliedAppearanceNames.append(appearance?.name)
            }
        )
        controller.start()

        settings.appearanceMode = .dark
        settings.appearanceMode = .system
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        await Task.yield()

        XCTAssertNil(window.appearance)
        XCTAssertEqual(appliedAppearanceNames.suffix(2), [nil, nil])
        controller.stop()
    }
}
