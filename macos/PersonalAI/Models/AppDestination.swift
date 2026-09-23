import Foundation

enum AppDestination: String, Hashable, Identifiable {
    case assistant
    case memory
    case skills
    case settings

    var id: Self { self }
}
