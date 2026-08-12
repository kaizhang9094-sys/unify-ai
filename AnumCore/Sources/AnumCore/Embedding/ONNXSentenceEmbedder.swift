import Foundation
import OnnxRuntimeBindings
import Tokenizers

@inline(__always)
private func embLog(_ msg: @autoclosure () -> String) {
#if DEBUG
    print(msg())
#endif
}

public final class ONNXSentenceEmbedder: MemoryEmbeddingProvider, @unchecked Sendable {

    public struct Config: Sendable {
        public var modelFileName: String = "model"
        public var modelFileExt: String = "onnx"

        public var tokenizerFileName: String = "tokenizer"
        public var tokenizerFileExt: String = "json"

        public var tokenizerConfigFileName: String = "tokenizer_config"
        public var tokenizerConfigFileExt: String = "json"

        public var modelConfigFileName: String = "config"
        public var modelConfigFileExt: String = "json"

        public var specialTokensMapFileName: String = "special_tokens_map"
        public var specialTokensMapFileExt: String = "json"

        public var vocabFileName: String = "vocab"
        public var vocabFileExt: String = "txt"

        public var maxSeqLen: Int = 256
        public var doLowerCase: Bool = true

        public var queryPrefix: String = "query: "
        public var passagePrefix: String = "passage: "

        public var clsToken: String = "[CLS]"
        public var sepToken: String = "[SEP]"
        public var padToken: String = "[PAD]"
        public var unkToken: String = "[UNK]"

        public var enableTraceLogs: Bool = true

        public init() {}
    }

    public enum InputKind: Sendable {
        case query
        case passage
        case raw
    }

    private let cfg: Config
    private let lock = NSLock()

    private var env: ORTEnv?
    private var session: ORTSession?

    // Preferred path
    private var jsonTokenizer: JSONTokenizerAdapter?

    // Fallback path
    private var wordPieceTokenizer: WordPieceTokenizer?

    public init(config: Config = .init()) {
        self.cfg = config
    }

    // MARK: - Public API

    public func embed(_ text: String) -> [Float]? {
        embedPassage(text)
    }

    public func embedQuery(_ text: String) -> [Float]? {
        embed(text, as: .query)
    }

    public func embedPassage(_ text: String) -> [Float]? {
        embed(text, as: .passage)
    }

    public func embedRaw(_ text: String) -> [Float]? {
        embed(text, as: .raw)
    }

    public func embed(_ text: String, as kind: InputKind) -> [Float]? {
        let prepared = prepareInput(text, as: kind)
        guard !prepared.isEmpty else {
            trace("embed skipped empty input kind=\(kind)")
            return nil
        }

        trace("embed begin kind=\(kind) chars=\(prepared.count)")

        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureLoaded()

            let encoded = try encode(prepared)

            guard let session else {
                trace("embed failed session=nil")
                return nil
            }

            trace(
                "encoded ids=\(encoded.inputIDs.count) " +
                "maskOn=\(encoded.attentionMask.reduce(0) { $0 + Int($1) }) " +
                "typeIds=\(encoded.tokenTypeIDs.count)"
            )

            let inputIds = try makeInt64Tensor(
                encoded.inputIDs,
                shape: [1, NSNumber(value: cfg.maxSeqLen)]
            )
            let attentionMask = try makeInt64Tensor(
                encoded.attentionMask,
                shape: [1, NSNumber(value: cfg.maxSeqLen)]
            )
            let tokenTypeIds = try makeInt64Tensor(
                encoded.tokenTypeIDs,
                shape: [1, NSNumber(value: cfg.maxSeqLen)]
            )

            let inputs: [String: ORTValue] = [
                "input_ids": inputIds,
                "attention_mask": attentionMask,
                "token_type_ids": tokenTypeIds
            ]

            let outputs = try session.run(
                withInputs: inputs,
                outputNames: ["last_hidden_state"],
                runOptions: nil
            )

            trace("run outputs keys=\(outputs.keys.sorted())")

            guard let out = outputs["last_hidden_state"] else {
                trace("missing expected output last_hidden_state")
                return nil
            }

            let pooled = try meanPoolLastHiddenState(
                out,
                attentionMask: encoded.attentionMask
            )

            let normalized = l2Normalize(pooled)
            trace("embed success dim=\(normalized.count)")
            return normalized
        } catch {
            trace("embed failed error=\(error)")
            return nil
        }
    }

    // MARK: - Input shaping

    private func prepareInput(_ text: String, as kind: InputKind) -> String {
        let cleaned = normalizeWhitespace(text)
        guard !cleaned.isEmpty else { return "" }

        switch kind {
        case .query:
            if cleaned.lowercased().hasPrefix(cfg.queryPrefix.lowercased()) {
                return cleaned
            }
            return cfg.queryPrefix + cleaned

        case .passage:
            if cleaned.lowercased().hasPrefix(cfg.passagePrefix.lowercased()) {
                return cleaned
            }
            return cfg.passagePrefix + cleaned

        case .raw:
            return cleaned
        }
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    // MARK: - Load

    private func ensureLoaded() throws {
        if env != nil, session != nil, (jsonTokenizer != nil || wordPieceTokenizer != nil) {
            return
        }

        trace("ensureLoaded starting")

        let modelURL = try requireResourceURL(
            fileName: cfg.modelFileName,
            fileExt: cfg.modelFileExt,
            subdir: "EmbeddingAssets",
            code: 2
        )

        if hasJSONTokenizerAssets() {
            do {
                let runtimeFolderURL = try prepareRuntimeTokenizerFolder()

                let tokenizerURL = runtimeFolderURL.appendingPathComponent("\(cfg.tokenizerFileName).\(cfg.tokenizerFileExt)")
                let tokenizerConfigURL = runtimeFolderURL.appendingPathComponent("\(cfg.tokenizerConfigFileName).\(cfg.tokenizerConfigFileExt)")
                let modelConfigURL = runtimeFolderURL.appendingPathComponent("\(cfg.modelConfigFileName).\(cfg.modelConfigFileExt)")
                let specialTokensURL = runtimeFolderURL.appendingPathComponent("\(cfg.specialTokensMapFileName).\(cfg.specialTokensMapFileExt)")

                trace(
                    "json tokenizer runtime assets " +
                    "tokenizerExists=\(FileManager.default.fileExists(atPath: tokenizerURL.path)) " +
                    "tokenizerConfigExists=\(FileManager.default.fileExists(atPath: tokenizerConfigURL.path)) " +
                    "modelConfigExists=\(FileManager.default.fileExists(atPath: modelConfigURL.path)) " +
                    "specialTokensExists=\(FileManager.default.fileExists(atPath: specialTokensURL.path)) " +
                    "folder=\(runtimeFolderURL.path)"
                )

                jsonTokenizer = try JSONTokenizerAdapter(
                    modelFolderURL: runtimeFolderURL,
                    maxSeqLen: cfg.maxSeqLen
                )

                trace("loaded tokenizer json path folder=\(runtimeFolderURL.path)")
            } catch {
                trace("json tokenizer load failed, falling back to vocab.txt error=\(error)")
                jsonTokenizer = nil
            }
        } else {
            trace("json tokenizer assets not complete, falling back to vocab.txt")
        }

        if jsonTokenizer == nil {
            let vocabURL = try requireResourceURL(
                fileName: cfg.vocabFileName,
                fileExt: cfg.vocabFileExt,
                subdir: "EmbeddingAssets",
                code: 1
            )

            let vocabText = try String(contentsOf: vocabURL, encoding: .utf8)
            let vocab = vocabText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            wordPieceTokenizer = try WordPieceTokenizer(
                vocab: vocab,
                doLowerCase: cfg.doLowerCase,
                clsToken: cfg.clsToken,
                sepToken: cfg.sepToken,
                padToken: cfg.padToken,
                unkToken: cfg.unkToken
            )

            trace("loaded fallback vocab path file=\(vocabURL.lastPathComponent) size=\(vocab.count)")
        }

        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let opts = try ORTSessionOptions()
        let sess = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)

        self.env = env
        self.session = sess

        trace(
            "loaded model=\(modelURL.lastPathComponent) " +
            "maxSeqLen=\(cfg.maxSeqLen) " +
            "tokenizerMode=\(jsonTokenizer != nil ? "json" : "wordpiece-fallback")"
        )
    }

    private func encode(_ text: String) throws -> Encoded {
        if let jsonTokenizer {
            return try jsonTokenizer.encode(text: text)
        }

        if let wordPieceTokenizer {
            return wordPieceTokenizer.encode(text: text, maxLen: cfg.maxSeqLen)
        }

        throw NSError(
            domain: "ONNXSentenceEmbedder",
            code: 50,
            userInfo: [NSLocalizedDescriptionKey: "No tokenizer is loaded."]
        )
    }

    // MARK: - Resource loading

    private func hasJSONTokenizerAssets() -> Bool {
        findResourceURL(
            fileName: cfg.tokenizerFileName,
            fileExt: cfg.tokenizerFileExt,
            subdir: "EmbeddingAssets"
        ) != nil
        &&
        findResourceURL(
            fileName: cfg.tokenizerConfigFileName,
            fileExt: cfg.tokenizerConfigFileExt,
            subdir: "EmbeddingAssets"
        ) != nil
        &&
        findResourceURL(
            fileName: cfg.modelConfigFileName,
            fileExt: cfg.modelConfigFileExt,
            subdir: "EmbeddingAssets"
        ) != nil
        &&
        findResourceURL(
            fileName: cfg.specialTokensMapFileName,
            fileExt: cfg.specialTokensMapFileExt,
            subdir: "EmbeddingAssets"
        ) != nil
    }

    private func prepareRuntimeTokenizerFolder() throws -> URL {
        let fileManager = FileManager.default

        let base = fileManager.temporaryDirectory
            .appendingPathComponent("ONNXSentenceEmbedder", isDirectory: true)
            .appendingPathComponent("EmbeddingAssetsRuntime", isDirectory: true)

        if fileManager.fileExists(atPath: base.path) {
            try? fileManager.removeItem(at: base)
        }

        try fileManager.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )

        try copyResourceIntoFolder(
            fileName: cfg.tokenizerFileName,
            fileExt: cfg.tokenizerFileExt,
            subdir: "EmbeddingAssets",
            destinationFolder: base
        )

        try copyResourceIntoFolder(
            fileName: cfg.tokenizerConfigFileName,
            fileExt: cfg.tokenizerConfigFileExt,
            subdir: "EmbeddingAssets",
            destinationFolder: base
        )

        try copyResourceIntoFolder(
            fileName: cfg.modelConfigFileName,
            fileExt: cfg.modelConfigFileExt,
            subdir: "EmbeddingAssets",
            destinationFolder: base
        )

        try copyResourceIntoFolder(
            fileName: cfg.specialTokensMapFileName,
            fileExt: cfg.specialTokensMapFileExt,
            subdir: "EmbeddingAssets",
            destinationFolder: base
        )

        if let vocabURL = findResourceURL(
            fileName: cfg.vocabFileName,
            fileExt: cfg.vocabFileExt,
            subdir: "EmbeddingAssets"
        ) {
            let dest = base.appendingPathComponent("\(cfg.vocabFileName).\(cfg.vocabFileExt)")
            if fileManager.fileExists(atPath: dest.path) {
                try? fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: vocabURL, to: dest)
        }

        return base
    }

    private func copyResourceIntoFolder(
        fileName: String,
        fileExt: String,
        subdir: String,
        destinationFolder: URL
    ) throws {
        let fileManager = FileManager.default

        let sourceURL = try requireResourceURL(
            fileName: fileName,
            fileExt: fileExt,
            subdir: subdir,
            code: 61
        )

        let destinationURL = destinationFolder
            .appendingPathComponent("\(fileName).\(fileExt)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        trace(
            "copied tokenizer asset " +
            "source=\(sourceURL.path) " +
            "dest=\(destinationURL.path)"
        )
    }
    
    private func findResourceURL(
        fileName: String,
        fileExt: String,
        subdir: String
    ) -> URL? {
        let bundles: [Bundle] = [
            Bundle.module,
            Bundle.main,
            Bundle(for: ONNXSentenceEmbedder.self)
        ]

        let fullName = "\(fileName).\(fileExt)"

        for bundle in bundles {
            if let url = bundle.url(forResource: fileName, withExtension: fileExt, subdirectory: subdir) {
                return url
            }

            if let resourceURL = bundle.resourceURL {
                let candidates: [URL] = [
                    resourceURL.appendingPathComponent(subdir, isDirectory: true).appendingPathComponent(fullName),
                    resourceURL.appendingPathComponent(fullName),
                    bundle.bundleURL.appendingPathComponent(subdir, isDirectory: true).appendingPathComponent(fullName),
                    bundle.bundleURL.appendingPathComponent(fullName),
                    bundle.bundleURL.appendingPathComponent("Contents/Resources/\(subdir)", isDirectory: true).appendingPathComponent(fullName),
                    bundle.bundleURL.appendingPathComponent("Contents/Resources/\(fullName)")
                ]

                for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func requireResourceURL(
        fileName: String,
        fileExt: String,
        subdir: String,
        code: Int
    ) throws -> URL {
        if let url = findResourceURL(fileName: fileName, fileExt: fileExt, subdir: subdir) {
            return url
        }

        let fullName = "\(fileName).\(fileExt)"
        let bundles: [Bundle] = [
            Bundle.module,
            Bundle.main,
            Bundle(for: ONNXSentenceEmbedder.self)
        ]

        let tried = bundles.map { bundle in
            let resourcePath = bundle.resourceURL?.path ?? "nil"
            return "\(bundle.bundleURL.lastPathComponent): bundle=\(bundle.bundleURL.path) resource=\(resourcePath)"
        }.joined(separator: " | ")

        throw NSError(
            domain: "ONNXSentenceEmbedder",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Missing \(subdir)/\(fullName); tried: \(tried)"
            ]
        )
    }

    // MARK: - ORT helpers

    private func makeInt64Tensor(_ data: [Int64], shape: [NSNumber]) throws -> ORTValue {
        var copy = data
        let byteCount = copy.count * MemoryLayout<Int64>.size
        let raw = NSMutableData(bytes: &copy, length: byteCount)

        return try ORTValue(
            tensorData: raw,
            elementType: ORTTensorElementDataType.int64,
            shape: shape
        )
    }

    private func meanPoolLastHiddenState(
        _ ortValue: ORTValue,
        attentionMask: [Int64]
    ) throws -> [Float] {
        let tensorData = try ortValue.tensorData() as Data
        let shape = try ortValue.tensorTypeAndShapeInfo().shape

        guard shape.count == 3 else {
            throw NSError(
                domain: "ONNXSentenceEmbedder",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected output rank: \(shape)"]
            )
        }

        let seqLen = min(shape[1].intValue, cfg.maxSeqLen)
        let hidden = shape[2].intValue

        guard hidden > 0 else {
            throw NSError(
                domain: "ONNXSentenceEmbedder",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Hidden dim invalid: \(shape)"]
            )
        }

        let floatCount = tensorData.count / MemoryLayout<Float>.size

        return tensorData.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: Float.self)
            let base = ptr.baseAddress!

            var sum = Array(repeating: Float(0), count: hidden)
            var denom: Float = 0

            for i in 0..<min(seqLen, attentionMask.count) {
                if attentionMask[i] == 0 { continue }
                denom += 1

                let offset = i * hidden
                if offset + hidden <= floatCount {
                    for h in 0..<hidden {
                        sum[h] += base[offset + h]
                    }
                }
            }

            if denom > 0 {
                let inv = 1.0 / denom
                for h in 0..<hidden {
                    sum[h] *= Float(inv)
                }
            }

            return sum
        }
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for x in vector { sum += x * x }
        let norm = sqrt(sum)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private func trace(_ message: String) {
        guard cfg.enableTraceLogs else { return }
        embLog("[ONNXSentenceEmbedder] \(message)")
    }
}

// MARK: - Shared encoded payload

private struct Encoded {
    let inputIDs: [Int64]
    let attentionMask: [Int64]
    let tokenTypeIDs: [Int64]
}

private final class LockedLoadState: @unchecked Sendable {
    private let lock = NSLock()
    private var _tokenizer: (any Tokenizer)?
    private var _error: Error?

    var tokenizer: (any Tokenizer)? {
        lock.lock()
        defer { lock.unlock() }
        return _tokenizer
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return _error
    }

    func setTokenizer(_ tokenizer: any Tokenizer) {
        lock.lock()
        _tokenizer = tokenizer
        lock.unlock()
    }

    func setError(_ error: Error) {
        lock.lock()
        _error = error
        lock.unlock()
    }
}

// MARK: - tokenizer.json adapter via Transformers

private final class JSONTokenizerAdapter {
    private static let loadQueue = DispatchQueue(
        label: "ONNXSentenceEmbedder.JSONTokenizerAdapter.load",
        qos: .userInitiated
    )

    private let tokenizer: any Tokenizer
    private let maxSeqLen: Int

    init(
        modelFolderURL: URL,
        maxSeqLen: Int
    ) throws {
        self.maxSeqLen = maxSeqLen

        let group = DispatchGroup()
        let state = LockedLoadState()

        group.enter()

        Self.loadQueue.async {
            Task(priority: .high) {
                do {
                    let tokenizer = try await AutoTokenizer.from(modelFolder: modelFolderURL)
                    state.setTokenizer(tokenizer)
                } catch {
                    state.setError(error)
                }
                group.leave()
            }
        }

        group.wait()

        if let capturedError = state.error {
            throw capturedError
        }

        guard let loadedTokenizer = state.tokenizer else {
            throw NSError(
                domain: "ONNXSentenceEmbedder",
                code: 60,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "AutoTokenizer.from(modelFolder:) returned nil tokenizer."
                ]
            )
        }

        self.tokenizer = loadedTokenizer
    }

    func encode(text: String) throws -> Encoded {
        var ids = tokenizer.encode(text: text).map(Int64.init)

        if ids.count > maxSeqLen {
            ids = Array(ids.prefix(maxSeqLen))
        }

        let nonPaddedCount = ids.count
        let padCount = max(0, maxSeqLen - nonPaddedCount)

        if padCount > 0 {
            ids += Array(repeating: 0, count: padCount)
        }

        let attentionMask =
            Array(repeating: Int64(1), count: nonPaddedCount) +
            Array(repeating: Int64(0), count: padCount)

        let tokenTypeIDs = Array(repeating: Int64(0), count: maxSeqLen)

        return Encoded(
            inputIDs: ids,
            attentionMask: attentionMask,
            tokenTypeIDs: tokenTypeIDs
        )
    }
}

// MARK: - Legacy fallback tokenizer

private final class WordPieceTokenizer {
    private let tokenToId: [String: Int64]
    private let doLowerCase: Bool

    private let cls: String
    private let sep: String
    private let pad: String
    private let unk: String

    private let clsId: Int64
    private let sepId: Int64
    private let padId: Int64
    private let unkId: Int64

    init(
        vocab: [String],
        doLowerCase: Bool,
        clsToken: String,
        sepToken: String,
        padToken: String,
        unkToken: String
    ) throws {
        var map: [String: Int64] = [:]
        map.reserveCapacity(vocab.count)

        for (i, tok) in vocab.enumerated() {
            map[tok] = Int64(i)
        }

        self.tokenToId = map
        self.doLowerCase = doLowerCase
        self.cls = clsToken
        self.sep = sepToken
        self.pad = padToken
        self.unk = unkToken

        guard
            let clsId = map[cls],
            let sepId = map[sep],
            let padId = map[pad],
            let unkId = map[unk]
        else {
            throw NSError(
                domain: "WordPieceTokenizer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing required special tokens in vocab.txt"]
            )
        }

        self.clsId = clsId
        self.sepId = sepId
        self.padId = padId
        self.unkId = unkId
    }

    func encode(text: String, maxLen: Int) -> Encoded {
        let normalized = doLowerCase ? text.lowercased() : text
        let words = basicTokenize(normalized)

        var ids: [Int64] = []
        ids.reserveCapacity(maxLen)

        ids.append(clsId)

        for word in words {
            let pieces = wordpiece(word)
            for piece in pieces {
                ids.append(tokenToId[piece] ?? unkId)
                if ids.count >= maxLen - 1 { break }
            }
            if ids.count >= maxLen - 1 { break }
        }

        ids.append(sepId)

        if ids.count > maxLen {
            ids = Array(ids.prefix(maxLen))
            ids[maxLen - 1] = sepId
        }

        var attentionMask = Array(repeating: Int64(0), count: maxLen)
        for i in 0..<min(ids.count, maxLen) {
            attentionMask[i] = 1
        }

        if ids.count < maxLen {
            ids += Array(repeating: padId, count: maxLen - ids.count)
        }

        let tokenTypeIDs = Array(repeating: Int64(0), count: maxLen)

        return Encoded(
            inputIDs: ids,
            attentionMask: attentionMask,
            tokenTypeIDs: tokenTypeIDs
        )
    }

    private func basicTokenize(_ text: String) -> [String] {
        let punctuation = CharacterSet.punctuationCharacters
        var output = ""
        output.reserveCapacity(text.count * 2)

        for scalar in text.unicodeScalars {
            if punctuation.contains(scalar) {
                output.append(" ")
                output.append(Character(scalar))
                output.append(" ")
            } else {
                output.append(Character(scalar))
            }
        }

        return output
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func wordpiece(_ token: String) -> [String] {
        if tokenToId[token] != nil {
            return [token]
        }

        let chars = Array(token)
        var start = 0
        var pieces: [String] = []

        while start < chars.count {
            var end = chars.count
            var current: String? = nil

            while start < end {
                let sub = String(chars[start..<end])
                let candidate = start == 0 ? sub : "##" + sub

                if tokenToId[candidate] != nil {
                    current = candidate
                    break
                }

                end -= 1
            }

            guard let found = current else {
                return [unk]
            }

            pieces.append(found)
            start = end
        }

        return pieces
    }
}
