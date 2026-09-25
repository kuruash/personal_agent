import Foundation

enum ModelRoute: String, Sendable { case fast, reasoning, vision }

struct ModelConfiguration: Sendable {
    let route: ModelRoute; let displayName: String; let exactPreferredID: String; let availabilityTokens: [String]; let supportsVision: Bool
    static let fast = Self(route: .fast, displayName: "Nemotron 3.5 Lightning 30B A3B", exactPreferredID: "nvidia/Nemotron-3.5-Lightning-30B-A3B", availabilityTokens: ["lightning", "30b"], supportsVision: false)
    static let reasoning = Self(route: .reasoning, displayName: "Nemotron 3 Ultra", exactPreferredID: "nvidia/Nemotron-3-Ultra-550b-a55b", availabilityTokens: ["ultra", "550b"], supportsVision: false)
    static let vision = Self(route: .vision, displayName: "Nemotron 3 Nano Omni 30B A3B Reasoning", exactPreferredID: "nvidia/Nemotron-3-Nano-Omni-30B-A3B", availabilityTokens: ["nano", "omni", "30b"], supportsVision: true)
    static func configuration(for route: ModelRoute) -> Self { switch route { case .fast: fast; case .reasoning: reasoning; case .vision: vision } }
}

struct RoutingContext: Sendable { let message: String; let hasVisualInput: Bool; let historyCount: Int; let toolCount: Int }

struct ModelRoutingDecision: Sendable { let route: ModelRoute; let reason: String; let configuration: ModelConfiguration }

struct ModelRouter: Sendable {
    func route(_ context: RoutingContext) -> ModelRoutingDecision {
        if context.hasVisualInput { return .init(route: .vision, reason: "visual_input_present", configuration: .vision) }
        let text = context.message.lowercased()
        let complexSignals = ["detailed plan", "compare", "contradict", "debug", "why is", "research", "across", "calendar and", "emails and", "files and", "multiple"]
        let mentionedSources = ["calendar", "email", "files", "projects", "memory", "profile"].reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let score = complexSignals.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } + (mentionedSources >= 3 ? 2 : 0) + (context.historyCount > 30 ? 1 : 0)
        if score >= 2 { return .init(route: .reasoning, reason: "complex_multi_source_or_reasoning_request", configuration: .reasoning) }
        return .init(route: .fast, reason: "default_simple_request", configuration: .fast)
    }
    func resolve(_ decision: ModelRoutingDecision, available: [String]) -> String? {
        let config = decision.configuration
        if available.contains(config.exactPreferredID) { return config.exactPreferredID }
        return available.first { id in let value = id.lowercased(); return config.availabilityTokens.allSatisfy(value.contains) }
    }
}
