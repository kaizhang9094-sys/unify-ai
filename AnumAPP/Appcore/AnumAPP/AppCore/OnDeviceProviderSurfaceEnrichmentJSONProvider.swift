import Foundation
import AnumCore

struct OnDeviceProviderSurfaceEnrichmentJSONProvider: AsyncProviderSurfaceEnrichmentJSONProvider, Sendable {
    private let runner: any ExchangeIntelligenceModelRunner
    private let runtimeMonitor: any ExchangeRuntimeActivityMonitor
    private let maxTokens: Int

    init(
        runner: any ExchangeIntelligenceModelRunner,
        runtimeMonitor: any ExchangeRuntimeActivityMonitor,
        maxTokens: Int = 480
    ) {
        self.runner = runner
        self.runtimeMonitor = runtimeMonitor
        self.maxTokens = max(128, maxTokens)
    }

    func isReadyForImmediateExtraction() async -> Bool {
        let runtime = await runtimeMonitor.snapshot()
        guard !runtime.isGenerating else { return false }
        let modeBusy = await AIRuntimeModeGate.shared.isBusy()
        guard !modeBusy else { return false }
        let streamBusy = await AIRuntimeStreamGate.shared.isBusy()
        return !streamBusy
    }

    func enrichProviderSurfaceJSON(prompt: String) async throws -> String {
        guard await isReadyForImmediateExtraction() else {
            throw OnDeviceProviderSurfaceEnrichmentError.modelBusy
        }

        let request = ExchangeIntelligenceModelRunRequest(
            task: .interpretation,
            prompt: prompt,
            maxTokens: maxTokens
        )
        return try await runner.run(request)
    }
}

private enum OnDeviceProviderSurfaceEnrichmentError: Error, Sendable, ProviderSurfaceEnrichmentBusyError {
    case modelBusy
}
