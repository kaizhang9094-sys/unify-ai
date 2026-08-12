import SwiftUI
import Combine

struct TraceViewer: View {
    @ObservedObject private var store = TraceStore.shared

    @Environment(\.horizontalSizeClass) private var hSize

    private var tracesSorted: [TurnTrace] {
        store.traces.sorted { $0.startedAt > $1.startedAt }
    }

    // ✅ Use an ID for selection (UUID is Hashable)
    @State private var selectedId: UUID?

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                // iOS 16+: modern navigation
                if hSize == .compact {
                    // iPhone: push navigation (selection-based split views are unreliable in compact width)
                    NavigationStack {
                        List {
                            ForEach(tracesSorted) { t in
                                NavigationLink(value: t.id) {
                                    TraceRow(trace: t)
                                }
                            }
                        }
                        .navigationTitle("Trace")
                        .toolbar {
                            Button("Clear") {
                                store.clearAll()
                                selectedId = nil
                            }
                        }
                        .navigationDestination(for: UUID.self) { id in
                            if let t = tracesSorted.first(where: { $0.id == id }) {
                                TraceDetail(trace: t)
                                    .navigationTitle("Details")
                            } else {
                                Text("Trace not found")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    // iPad / Mac: split view is great
                    NavigationSplitView {
                        List(selection: $selectedId) {
                            ForEach(tracesSorted) { t in
                                TraceRow(trace: t)
                                    .tag(t.id)
                            }
                        }
                        .toolbar {
                            Button("Clear") {
                                store.clearAll()
                                selectedId = nil
                            }
                        }
                    } detail: {
                        if let t = selectedTrace {
                            TraceDetail(trace: t)
                        } else {
                            Text("No traces yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                // iOS 15: legacy navigation
                NavigationView {
                    List {
                        ForEach(tracesSorted) { t in
                            NavigationLink(destination: TraceDetail(trace: t)
                                .navigationBarTitle("Details", displayMode: .inline)
                            ) {
                                TraceRow(trace: t)
                            }
                        }
                    }
                    .navigationBarTitle("Trace", displayMode: .inline)
                    .toolbar {
                        Button("Clear") {
                            store.clearAll()
                            selectedId = nil
                        }
                    }

                    // iPad detail placeholder (NavigationView 2-column behavior)
                    Text("No traces yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            // default selection to newest trace
            if selectedId == nil {
                selectedId = tracesSorted.first?.id
            }
        }
        .onChangeCompat(of: store.traces.count) {
            // keep selection sane after updates/clears
            if let id = selectedId, store.traces.contains(where: { $0.id == id }) {
                return
            }
            selectedId = tracesSorted.first?.id
        }
    }

    private var selectedTrace: TurnTrace? {
        if let id = selectedId {
            return tracesSorted.first(where: { $0.id == id })
        }
        return tracesSorted.first
    }
}

private extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, _ in
                action()
            }
        } else {
            self.onChange(of: value) { _ in
                action()
            }
        }
    }
}

private struct TraceRow: View {
    let trace: TurnTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trace.identityName).font(.subheadline).bold()
                Spacer()
                Text("\(trace.durationMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(trace.userText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let err = trace.error {
                Text("Error: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TraceDetail: View {
    let trace: TurnTrace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Summary") {
                    VStack(alignment: .leading, spacing: 6) {
                        row("ID", trace.id.uuidString)
                        row("Started", trace.startedAt.formatted())
                        row("Ended", trace.endedAt?.formatted() ?? "—")
                        row("Duration", "\(trace.durationMs) ms")
                        row("Model", trace.modelPath)
                        row("Identity", "\(trace.identityName) (\(trace.identityVersionId))")
                        row("Prompt chars", "\(trace.promptChars)")
                        row("Output chars", "\(trace.outputChars)")
                        if let err = trace.error {
                            row("Error", err)
                        }
                    }
                }

                GroupBox("User Text") {
                    Text(trace.userText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Prompt Preview") {
                    Text(trace.promptPreview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // MARK: - Memory injection diagnostics (Phase 3 Step 5)
                if let memUI = memorySectionUI() {
                    GroupBox("Memory Injection") {
                        memUI
                    }
                }

                if !trace.warnings.isEmpty {
                    GroupBox("Warnings") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(trace.warnings, id: \.self) { w in
                                Text("• \(w)").foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(v)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    // Build a small UI section for whatever memory debug fields exist on TurnTrace.
    // Uses Mirror so TraceViewer doesn’t hard-depend on exact property names.
    private func memorySectionUI() -> AnyView? {
        // Try several likely containers first
        let memContainer = mirrorChild(of: trace, named: "memoryDebug")
            ?? mirrorChild(of: trace, named: "memoryDebugInfo")
            ?? mirrorChild(of: trace, named: "memoryDebuggingInfo")
            ?? mirrorChild(of: trace, named: "memory")

        // Pull fields either from the container or directly from TurnTrace
        let injectedChars = (mirrorInt(in: memContainer, named: "injectedChars")
                             ?? mirrorInt(in: memContainer, named: "memoryInjectedChars")
                             ?? mirrorInt(in: trace, named: "memoryInjectedChars"))

        let hits = (mirrorInt(in: memContainer, named: "hits")
                    ?? mirrorInt(in: memContainer, named: "retrievalHits")
                    ?? mirrorInt(in: trace, named: "memoryHits"))

        let queryHash = (mirrorString(in: memContainer, named: "queryHash")
                         ?? mirrorString(in: memContainer, named: "retrievalQueryHash")
                         ?? mirrorString(in: trace, named: "memoryQueryHash"))

        let preview = (mirrorString(in: memContainer, named: "injectedPreview")
                       ?? mirrorString(in: memContainer, named: "preview")
                       ?? mirrorString(in: trace, named: "memoryInjectedPreview")
                       ?? mirrorString(in: trace, named: "memoryPreview"))

        let memError = (mirrorString(in: memContainer, named: "error")
                        ?? mirrorString(in: trace, named: "memoryError"))

        // Fallback: if TurnTrace doesn't expose memory debug fields yet, try to parse the injected
        // MEMORY_CONTEXT block from the prompt preview.
        var injectedCharsV = injectedChars
        var hitsV = hits
        var queryHashV = queryHash
        var previewV = preview
        let memErrorV = memError

        if injectedCharsV == nil && previewV == nil {
            if let block = extractMemoryBlock(from: trace.promptPreview) {
                previewV = block
                injectedCharsV = block.count
                if hitsV == nil { hitsV = 0 }
                if queryHashV == nil { queryHashV = "" }
            }
        }

        // If nothing exists, don’t render the section.
        if injectedCharsV == nil && hitsV == nil && queryHashV == nil && previewV == nil && memErrorV == nil {
            return nil
        }

        let hashPrefix: String? = {
            guard let q = queryHashV, !q.isEmpty else { return nil }
            return String(q.prefix(10))
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                if let hitsV {
                    row("Hits", "\(hitsV)")
                }
                if let hashPrefix {
                    row("Query", hashPrefix)
                }
                if let injectedCharsV {
                    row("Injected chars", "\(injectedCharsV)")
                }
                if let memErrorV {
                    row("Memory error", memErrorV)
                }
                if let previewV, !previewV.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text(previewV)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    private func extractMemoryBlock(from prompt: String) -> String? {
        // Common headers we might use
        let headers = ["### MEMORY_CONTEXT", "## MEMORY_CONTEXT", "MEMORY_CONTEXT"]
        guard let startRange = headers.compactMap({ prompt.range(of: $0) }).first else {
            return nil
        }

        let searchStart = startRange.upperBound
        var endIndex = prompt.endIndex

        // Stop at the next IM boundary if present
        if let endRange = prompt.range(of: "<|im_end|>", range: searchStart..<prompt.endIndex) {
            endIndex = endRange.lowerBound
        } else if let endRange = prompt.range(of: "\n## ", range: searchStart..<prompt.endIndex) {
            // Or stop at the next section header if we don't have IM tokens
            endIndex = endRange.lowerBound
        }

        let block = String(prompt[startRange.lowerBound..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return block.isEmpty ? nil : block
    }

    private func mirrorChild(of any: Any, named name: String) -> Any? {
        for child in Mirror(reflecting: any).children {
            if child.label == name { return child.value }
        }
        return nil
    }

    private func mirrorInt(in any: Any?, named name: String) -> Int? {
        guard let any else { return nil }
        for child in Mirror(reflecting: any).children {
            if child.label == name {
                if let v = child.value as? Int { return v }
                if let v = child.value as? Int64 { return Int(v) }
                if let v = child.value as? UInt { return Int(v) }
                if let v = child.value as? UInt64 { return Int(v) }
            }
        }
        return nil
    }

    private func mirrorString(in any: Any?, named name: String) -> String? {
        guard let any else { return nil }
        for child in Mirror(reflecting: any).children {
            if child.label == name {
                return child.value as? String
            }
        }
        return nil
    }
}
