import Foundation

@main
private struct ModelRouterHarness {
    static func main() throws {
        let router = ModelRouter()
        func route(_ text: String, visual: Bool = false) -> ModelRoute { router.route(.init(message: text, hasVisualInput: visual, historyCount: 2, toolCount: 5)).route }
        guard route("What's on my calendar today?") == .fast,
              route("Summarize this email.") == .fast,
              route("Find PDFs in Downloads.") == .fast,
              route("Create an event tomorrow at 5 PM.") == .fast,
              route("Make this shorter.") == .fast else { throw NSError(domain: "ModelRouter", code: 1) }
        guard route("Look through my calendar, emails, files, and projects and build a detailed plan for next week.") == .reasoning,
              route("Compare these documents, identify contradictions, and determine what actions I should take.") == .reasoning else { throw NSError(domain: "ModelRouter", code: 2) }
        guard route("What is happening here?", visual: true) == .vision,
              route("What does this screenshot mean?") == .fast else { throw NSError(domain: "ModelRouter", code: 3) }
        let models = [ModelConfiguration.fast.exactPreferredID, ModelConfiguration.reasoning.exactPreferredID, ModelConfiguration.vision.exactPreferredID]
        guard router.resolve(router.route(.init(message: "hi", hasVisualInput: false, historyCount: 0, toolCount: 0)), available: models) == ModelConfiguration.fast.exactPreferredID else { throw NSError(domain: "ModelRouter", code: 4) }
        print("ALL MODEL ROUTER TESTS PASSED")
    }
}
