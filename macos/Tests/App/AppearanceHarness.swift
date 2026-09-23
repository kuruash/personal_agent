import SwiftUI

private enum AppearanceTestError: Error { case failed(String) }

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw AppearanceTestError.failed(message) }
}

@main
@MainActor
private struct AppearanceHarness {
    static func main() throws {
        try require(AppAppearance.system.colorScheme == nil, "System must not force a color scheme")
        try require(AppAppearance.light.colorScheme == .light, "Light mapping failed")
        try require(AppAppearance.dark.colorScheme == .dark, "Dark mapping failed")

        let suiteName = "PersonalAI-AppearanceTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AppearanceTestError.failed("Could not create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppearanceStore(defaults: defaults)
        try require(first.selection == .system, "Missing preference did not default to System")
        first.selection = .dark
        try require(AppearanceStore(defaults: defaults).selection == .dark, "Dark preference did not persist")
        first.selection = .light
        try require(AppearanceStore(defaults: defaults).selection == .light, "Light preference did not persist")
        first.selection = .system
        try require(AppearanceStore(defaults: defaults).selection == .system, "System preference did not persist")

        defaults.set("unsupported", forKey: AppAppearance.storageKey)
        try require(AppearanceStore(defaults: defaults).selection == .system, "Invalid preference did not fall back safely")
        print("ALL APPEARANCE TESTS PASSED")
    }
}
