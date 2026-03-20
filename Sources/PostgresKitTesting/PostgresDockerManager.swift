import Foundation

public final class PostgresDockerManager: @unchecked Sendable {
    public static let shared = PostgresDockerManager()
    public static let fixtureVersion = "2026-03-20.1"

    public var version: String {
        ProcessInfo.processInfo.environment["POSTGRES_VERSION"] ?? "17"
    }

    public var port: Int {
        Int(ProcessInfo.processInfo.environment["POSTGRES_PORT"] ?? "54321") ?? 54321
    }

    public let password = "postgres"
    public let username = "postgres"
    public let database = "postgres"

    private let lock = NSLock()
    private var containerId: String?
    private var isStarted = false
    private var lastStartupReusedContainer = false
    private var lastStartupRecreatedContainer = false

    private init() {}

    private var containerName: String {
        "postgres-wire-test-\(version)-agent-\(port)"
    }

    private var fixtureMarkerPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("\(containerName)-fixture-\(Self.fixtureVersion).ready")
    }

    private var sampleDataPath: String {
        let sourceURL = URL(fileURLWithPath: #filePath)
        return sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/PostgresKitTests/Support/SampleData.sql")
            .path
    }

    public func startIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let dockerPath = findDockerExecutable() else {
            throw PostgresFixtureError.unavailable("Docker executable not found.")
        }

        if isStarted {
            exportEnvironment()
            return
        }

        try verifyDockerIsRunning(dockerPath: dockerPath)

        var reusedExistingContainer = false
        var recreatedContainer = false

        if let existingContainerId = try existingContainerID(named: containerName, dockerPath: dockerPath) {
            containerId = existingContainerId
            reusedExistingContainer = true
        } else {
            try stopContainersSharingPort(dockerPath: dockerPath)
            try startFreshContainer(dockerPath: dockerPath)
            recreatedContainer = true
        }

        try waitForReady(dockerPath: dockerPath)
        lastStartupReusedContainer = reusedExistingContainer
        lastStartupRecreatedContainer = recreatedContainer
        isStarted = true
        exportEnvironment()
    }

    public func ensureFixture() throws -> PostgresFixtureReport {
        do {
            try startIfNeeded()
            let validations = try validateOrRepairFixture()
            return PostgresFixtureReport(
                image: "postgres:\(version)",
                port: port,
                reusedContainer: lastStartupReusedContainer,
                recreatedContainer: lastStartupRecreatedContainer,
                fixtureVersion: Self.fixtureVersion,
                validations: validations
            )
        } catch {
            try recreateFixtureContainer()
            try startIfNeeded()
            let validations = try validateOrRepairFixture()
            return PostgresFixtureReport(
                image: "postgres:\(version)",
                port: port,
                reusedContainer: false,
                recreatedContainer: true,
                fixtureVersion: Self.fixtureVersion,
                validations: validations
            )
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard let id = containerId, let dockerPath = findDockerExecutable() else { return }
        let process = createDockerProcess(executable: dockerPath, arguments: ["stop", id])
        try? process.run()
        process.waitUntilExit()
        containerId = nil
        isStarted = false
    }

    private func validateOrRepairFixture() throws -> [String] {
        if !FileManager.default.fileExists(atPath: fixtureMarkerPath) || !isFixtureValid() {
            try loadFixture()
        }

        guard isFixtureValid() else {
            throw PostgresFixtureError.unavailable("Postgres fixture validation failed after reload.")
        }

        _ = FileManager.default.createFile(atPath: fixtureMarkerPath, contents: Data(), attributes: nil)
        return [
            "container-ready",
            "db:\(database)",
            "schema:app",
            "schema:audit",
            "table:app.users",
            "type:public.mood",
            "extension:uuid-ossp",
            "role:test_readonly"
        ]
    }

    private func isFixtureValid() -> Bool {
        let sql = """
        SELECT
            EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app')::int,
            EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'audit')::int,
            EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'users')::int,
            EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mood')::int,
            EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_readonly')::int,
            EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp')::int;
        """

        do {
            let output = try execPSQL(sql)
            let values = output.replacingOccurrences(of: "|", with: " ")
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            return values.count >= 6 && values.prefix(6).allSatisfy { $0 == "1" }
        } catch {
            return false
        }
    }

    private func loadFixture() throws {
        guard FileManager.default.fileExists(atPath: sampleDataPath) else {
            throw PostgresFixtureError.unavailable("SampleData.sql not found at \(sampleDataPath)")
        }

        let dropSQL = """
        DROP SCHEMA IF EXISTS app CASCADE;
        DROP SCHEMA IF EXISTS audit CASCADE;
        DROP SCHEMA IF EXISTS archive CASCADE;
        DROP ROLE IF EXISTS test_readonly;
        DROP ROLE IF EXISTS test_readwrite;
        DROP ROLE IF EXISTS test_app_user;
        """

        _ = try? execPSQL(dropSQL)
        let sqlContent = try String(contentsOfFile: sampleDataPath, encoding: .utf8)
        _ = try execPSQL(sqlContent)
    }

    private func recreateFixtureContainer() throws {
        guard let dockerPath = findDockerExecutable() else {
            throw PostgresFixtureError.unavailable("Docker executable not found while recreating Postgres fixture.")
        }

        if let existingContainerId = try existingContainerID(named: containerName, dockerPath: dockerPath) {
            let stop = createDockerProcess(executable: dockerPath, arguments: ["rm", "-f", existingContainerId])
            stop.standardOutput = FileHandle.nullDevice
            stop.standardError = FileHandle.nullDevice
            try? stop.run()
            stop.waitUntilExit()
        }

        try? FileManager.default.removeItem(atPath: fixtureMarkerPath)
        containerId = nil
        isStarted = false
        lastStartupReusedContainer = false
        lastStartupRecreatedContainer = true
    }

    private func exportEnvironment() {
        setenv("POSTGRES_HOST", "127.0.0.1", 1)
        setenv("POSTGRES_PORT", "\(port)", 1)
        setenv("POSTGRES_USERNAME", username, 1)
        setenv("POSTGRES_PASSWORD", password, 1)
        setenv("POSTGRES_DATABASE", database, 1)
        setenv("POSTGRES_FIXTURE_VERSION", Self.fixtureVersion, 1)
    }

    private func findDockerExecutable() -> String? {
        let commonPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker", "/bin/docker"]
        let fm = FileManager.default
        return commonPaths.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    private func verifyDockerIsRunning(dockerPath: String) throws {
        let process = createDockerProcess(executable: dockerPath, arguments: ["info"])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PostgresFixtureError.unavailable("Docker is not running.")
        }
    }

    private func createDockerProcess(executable: String, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        let dockerDir = (executable as NSString).deletingLastPathComponent
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(dockerDir):/usr/local/bin:/opt/homebrew/bin:\(currentPath)"
        env["DOCKER_CONFIG"] = ensureSanitizedDockerConfigDirectory()
        process.environment = env
        return process
    }

    private func ensureSanitizedDockerConfigDirectory() -> String {
        let fileManager = FileManager.default
        let configDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("postgres-wire-docker-config", isDirectory: true)
        let configFileURL = configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)

        try? fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        var sanitizedConfig: [String: Any] = [:]
        if let sourceConfigURL = dockerConfigSourceURL(),
           let data = try? Data(contentsOf: sourceConfigURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            sanitizedConfig = object
            sanitizedConfig.removeValue(forKey: "credsStore")
            sanitizedConfig.removeValue(forKey: "credHelpers")
        }

        if let encoded = try? JSONSerialization.data(withJSONObject: sanitizedConfig, options: [.prettyPrinted, .sortedKeys]) {
            try? encoded.write(to: configFileURL, options: .atomic)
        } else {
            try? Data("{}".utf8).write(to: configFileURL, options: .atomic)
        }

        return configDirectoryURL.path
    }

    private func dockerConfigSourceURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let configuredDirectory = environment["DOCKER_CONFIG"], !configuredDirectory.isEmpty {
            return URL(fileURLWithPath: configuredDirectory, isDirectory: true)
                .appendingPathComponent("config.json", isDirectory: false)
        }

        let homeDirectory = environment["HOME"] ?? NSHomeDirectory()
        guard !homeDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".docker/config.json", isDirectory: false)
    }

    private func existingContainerID(named name: String, dockerPath: String) throws -> String? {
        let process = createDockerProcess(executable: dockerPath, arguments: ["ps", "-aq", "--filter", "name=^\(name)$"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let containerID = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let containerID, !containerID.isEmpty else { return nil }
        return containerID
    }

    private func stopContainersSharingPort(dockerPath: String) throws {
        let process = createDockerProcess(executable: dockerPath, arguments: ["ps", "-aq", "--filter", "name=^postgres-wire-test-.*-\(port)$"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return }
        let identifiers = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []
        for identifier in identifiers where !identifier.isEmpty {
            let stop = createDockerProcess(executable: dockerPath, arguments: ["rm", "-f", identifier])
            stop.standardOutput = FileHandle.nullDevice
            stop.standardError = FileHandle.nullDevice
            try? stop.run()
            stop.waitUntilExit()
        }
        try? FileManager.default.removeItem(atPath: fixtureMarkerPath)
    }

    private func startFreshContainer(dockerPath: String) throws {
        try? FileManager.default.removeItem(atPath: fixtureMarkerPath)
        let process = createDockerProcess(executable: dockerPath, arguments: [
            "run", "-d", "--rm",
            "--name", containerName,
            "-p", "\(port):5432",
            "-e", "POSTGRES_PASSWORD=\(password)",
            "postgres:\(version)"
        ])

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 || output.isEmpty {
            let errorOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PostgresFixtureError.unavailable("Failed to start Docker container: \(errorOutput)")
        }

        containerId = output
    }

    private func waitForReady(dockerPath: String) throws {
        for _ in 1...45 {
            let process = createDockerProcess(executable: dockerPath, arguments: ["exec", containerId!, "pg_isready", "-U", username])
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        throw PostgresFixtureError.unavailable("Postgres failed to become ready in time.")
    }

    private func execPSQL(_ sql: String) throws -> String {
        guard let dockerPath = findDockerExecutable() else {
            throw PostgresFixtureError.unavailable("Docker executable not found while running psql.")
        }

        let process = createDockerProcess(executable: dockerPath, arguments: [
            "exec", "-i", containerId!, "psql", "-U", username, "-d", database, "-v", "ON_ERROR_STOP=1", "-At"
        ])

        let inputPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        if let data = sql.data(using: .utf8) {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let errorOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PostgresFixtureError.unavailable("Failed to execute psql fixture command: \(errorOutput)")
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
