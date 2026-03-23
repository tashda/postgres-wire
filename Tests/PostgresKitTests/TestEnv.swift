import Foundation
import Logging

enum TestEnv {
    private static let logger = Logger(label: "postgres.wire.tests")
    static func loadDotEnv() {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let envPath = (cwd as NSString).appendingPathComponent(".env")
        guard fm.fileExists(atPath: envPath) else { return }
        if let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if let eq = trimmed.firstIndex(of: "=") {
                    let key = String(trimmed[..<eq])
                    let value = String(trimmed[trimmed.index(after: eq)...])
                    setenv(key, value, 1)
                }
            }
        }
    }

    private static func getEnv(_ key: String) -> String? {
        // Try getenv first (for setenv compatibility)
        if let value = getenv(key) {
            return String(cString: value)
        }
        // Fallback to ProcessInfo
        return ProcessInfo.processInfo.environment[key]
    }

    static var isConfigured: Bool {
        let host = getEnv("POSTGRES_HOST")
        let useDocker = getEnv("USE_DOCKER")
        let configured = host != nil || useDocker == "1"
        if !configured {
            logger.warning("TestEnv NOT configured. POSTGRES_HOST: \(host ?? "nil"), USE_DOCKER: \(useDocker ?? "nil")")
        }
        return configured
    }

    static var host: String {
        getEnv("POSTGRES_HOST") ?? "127.0.0.1"
    }

    static var port: Int {
        if let portStr = getEnv("POSTGRES_PORT"),
           let port = Int(portStr) {
            return port
        }
        return 5432
    }

    static var username: String {
        getEnv("POSTGRES_USERNAME") ?? "postgres"
    }

    static var password: String? {
        getEnv("POSTGRES_PASSWORD") ?? "postgres"
    }

    static var database: String {
        getEnv("POSTGRES_DATABASE") ?? "postgres"
    }

    static var useTLS: Bool {
        (getEnv("POSTGRES_TLS") ?? "false").lowercased() == "true"
    }
}
