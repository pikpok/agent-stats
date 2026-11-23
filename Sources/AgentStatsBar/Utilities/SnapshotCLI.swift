import Foundation

enum SnapshotCLI {
    @MainActor
    static func dumpSnapshot(model: AppModel = AppModel(), write: (String) -> Void = { print($0) }) async {
        await model.refresh()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(model.snapshot)
            if let output = String(data: data, encoding: .utf8) {
                write(output)
            }
        } catch {
            fputs("Failed to encode snapshot: \(error)\n", stderr)
        }
    }

    static func installClaudeHelper() async {
        let result = ClaudeStatuslineHelperInstaller().install()
        print(result.userMessage)
    }
}
