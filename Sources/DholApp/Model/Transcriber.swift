import Foundation
import HuggingFace
import MLX
import MLXAudioSTT

/// Loads the speech model and turns 16 kHz mono samples into text.
actor Transcriber {
    /// Parakeet TDT 0.6B v3.
    ///
    /// Its vocabulary carries punctuation and capitals, so dictation arrives
    /// ready to use instead of as a lowercase run-on, and it covers 25
    /// languages. Check that before swapping in any replacement: several
    /// Parakeet variants have neither in their vocabulary, and a model that
    /// has no period token cannot produce one however clearly you say it.
    static let modelID = "mlx-community/parakeet-tdt-0.6b-v3"

    /// What the model is doing before it is usable.
    ///
    /// There is deliberately no byte count here. The loader exposes no progress
    /// callback, and URLSession buffers the whole download into a CFNetwork
    /// temp file, only moving it into the cache once complete — so during the
    /// download there is nothing in the cache to measure. Reporting a
    /// percentage would mean inventing one.
    enum Preparation: Equatable, Sendable {
        case downloading
        case loading
    }

    private var model: (any STTGenerationModel)?

    func load(onProgress: @escaping @Sendable (Preparation) -> Void) async throws {
        guard model == nil else { return }

        let watcher = Task { await Self.reportPreparation(to: onProgress) }
        defer { watcher.cancel() }

        model = try await STT.loadModel(modelRepo: Self.modelID, modelType: "parakeet")
    }

    func transcribe(_ samples: [Float]) throws -> String {
        guard let model else { return "" }
        let output = model.generate(audio: MLXArray(samples))
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Distinguishes downloading from loading by the one thing that is actually
    /// observable: whether the weights have landed in the cache yet.
    private static func reportPreparation(
        to onProgress: @escaping @Sendable (Preparation) -> Void
    ) async {
        guard let repo = Repo.ID(rawValue: modelID) else { return }
        let directory = HubCache.default.repoDirectory(repo: repo, kind: .model)

        while !Task.isCancelled {
            onProgress(weightsAreCached(in: directory) ? .loading : .downloading)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func weightsAreCached(in directory: URL) -> Bool {
        let snapshots = directory.appendingPathComponent("snapshots", isDirectory: true)
        guard let entries = FileManager.default.enumerator(
            at: snapshots,
            includingPropertiesForKeys: nil
        ) else { return false }

        for case let url as URL in entries where url.pathExtension == "safetensors" {
            return true
        }
        return false
    }
}
