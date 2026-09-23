import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var windowAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct WindowAppearanceController: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateWindow(for: nsView)
    }

    private func updateWindow(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.appearance = appearance.windowAppearance
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var selection: AppAppearance {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: AppAppearance.storageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: AppAppearance.storageKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
