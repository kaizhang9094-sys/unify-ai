import Foundation
import AnumCore

struct OnDeviceSearchIntentJSONProvider: AsyncSearchIntentJSONProvider, Sendable {
    private let runner: any ExchangeIntelligenceModelRunner
    private let runtimeMonitor: any ExchangeRuntimeActivityMonitor
    private let maxTokens: Int

    init(
        runner: any ExchangeIntelligenceModelRunner,
        runtimeMonitor: any ExchangeRuntimeActivityMonitor,
        maxTokens: Int = ExchangeIntelligenceTaskTokenBudget.searchIntentExtractionMaxTokens
    ) {
        self.runner = runner
        self.runtimeMonitor = runtimeMonitor
        self.maxTokens = max(64, maxTokens)
    }

    func isReadyForImmediateExtraction() async -> Bool {
        let runtime = await runtimeMonitor.snapshot()
        guard !runtime.isGenerating else { return false }
        let streamBusy = await AIRuntimeStreamGate.shared.isBusy()
        guard !streamBusy else { return false }

        // Secretary mode supports nested extraction while holding `AIRuntimeModeGate` (.secretary).
        // Block only when Companion owns the runtime (cross-mode conflict).
        let snap = await AIRuntimeModeGate.shared.snapshot()
        if snap.activeMode == .companion {
            return false
        }
        return true
    }

    func extractSearchIntentJSON(prompt: String) async throws -> String {
        guard await isReadyForImmediateExtraction() else {
            throw OnDeviceSearchIntentProviderError.modelBusy
        }

        let request = ExchangeIntelligenceModelRunRequest(
            task: .searchIntentExtraction,
            prompt: prompt,
            maxTokens: maxTokens
        )
        #if DEBUG
        print(
            "[SearchIntentExtraction] requestedMaxTokens=\(maxTokens) " +
            "configuredMaxTokens=\(ExchangeIntelligenceTaskTokenBudget.searchIntentExtractionMaxTokens) " +
            "task=searchIntentExtraction"
        )
        #endif
        return try await runner.run(request)
    }
}

private enum OnDeviceSearchIntentProviderError: Error, Sendable, SearchIntentProviderBusyError {
    case modelBusy
}
