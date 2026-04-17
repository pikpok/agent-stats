import Foundation

enum SnapshotCLI {
    static func dumpSnapshot() async {
        let helperInstaller = ClaudeStatuslineHelperInstaller()
        async let codexSnapshot = CodexUsageProvider().fetch()
        async let claudeSnapshot = ClaudeUsageProvider(helperInstaller: helperInstaller).fetch()
        async let cursorSnapshot = CursorUsageProvider().fetch()
        let snapshot = AppSnapshot(
            fetchedAt: Date(),
            services: await [codexSnapshot, claudeSnapshot, cursorSnapshot]
                .sorted { $0.service.sortOrder < $1.service.sortOrder }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(snapshot)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
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
