import Foundation
import XCTest

/// A utility to manage a PostgreSQL instance via Docker for integration testing.
public class PostgresDockerManager: @unchecked Sendable {
    public static let shared = PostgresDockerManager()
    
    public let version: String
    public let port: Int
    public let password = "postgres"
    public let username = "postgres"
    public let database = "postgres"
    
    private var containerId: String?
    private let lock = NSLock()
    private var isStarted = false
    
    private init() {
        self.version = ProcessInfo.processInfo.environment["POSTGRES_VERSION"] ?? "latest"
        self.port = Int(ProcessInfo.processInfo.environment["POSTGRES_PORT"] ?? "54321") ?? 54321
    }
    
    private func findDockerExecutable() -> String? {
        let commonPaths = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            "/bin/docker"
        ]
        
        let fm = FileManager.default
        for path in commonPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func createDockerProcess(executable: String, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        var env = ProcessInfo.processInfo.environment
        let dockerDir = (executable as NSString).deletingLastPathComponent
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(dockerDir):/usr/local/bin:/opt/homebrew/bin:\(currentPath)"
        process.environment = env
        
        return process
    }
    
    public func startIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isStarted else { return }
        
        guard let dockerPath = findDockerExecutable() else {
            throw NSError(domain: "PostgresDockerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Docker executable not found."])
        }
        
        print("🚀 Starting Postgres \(version) on port \(port)...")
        
        let checkProcess = createDockerProcess(executable: dockerPath, arguments: ["info"])
        checkProcess.standardOutput = FileHandle.nullDevice
        checkProcess.standardError = FileHandle.nullDevice
        
        try checkProcess.run()
        checkProcess.waitUntilExit()
        if checkProcess.terminationStatus != 0 {
            throw NSError(domain: "PostgresDockerManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Docker Desktop is not running."])
        }

        let process = createDockerProcess(executable: dockerPath, arguments: [
            "run", "-d",
            "--rm",
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
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if process.terminationStatus != 0 || output.isEmpty {
            throw NSError(domain: "PostgresDockerManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to start Docker container: \(errorOutput)"])
        }
        
        self.containerId = output
        print("📦 Container started: \(output)")
        
        try waitForReady(dockerPath: dockerPath)
        
        // Extra stabilization sleep
        Thread.sleep(forTimeInterval: 2.0)
        
        // Find and load sample data
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        print("📁 Current Directory: \(cwd)")
        
        // Try multiple possible locations for the SQL file
        let possiblePaths = [
            (cwd as NSString).appendingPathComponent("Tests/PostgresKitTests/Support/SampleData.sql"),
            (cwd as NSString).appendingPathComponent("Support/SampleData.sql"),
            "/Users/k/Development/postgres-wire/Tests/PostgresKitTests/Support/SampleData.sql" // Absolute fallback
        ]
        
        var loaded = false
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                print("📄 Found sample data at: \(path)")
                try runSQLFile(at: path, dockerPath: dockerPath)
                loaded = true
                break
            }
        }
        
        if !loaded {
            print("⚠️ Warning: SampleData.sql not found in any of the expected locations.")
        }
        
        setenv("POSTGRES_HOST", "127.0.0.1", 1)
        setenv("POSTGRES_PORT", "\(port)", 1)
        setenv("POSTGRES_USERNAME", username, 1)
        setenv("POSTGRES_PASSWORD", password, 1)
        setenv("POSTGRES_DATABASE", database, 1)
        
        isStarted = true
        
        atexit {
            PostgresDockerManager.shared.stop()
        }
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard let id = containerId, let dockerPath = findDockerExecutable() else { return }
        print("🛑 Stopping container \(id)...")
        
        let process = createDockerProcess(executable: dockerPath, arguments: ["stop", id])
        try? process.run()
        process.waitUntilExit()
        self.containerId = nil
        self.isStarted = false
    }
    
    private func waitForReady(dockerPath: String) throws {
        print("⏳ Waiting for Postgres to be ready...")
        let maxRetries = 45
        for i in 1...maxRetries {
            let process = createDockerProcess(executable: dockerPath, arguments: ["exec", containerId!, "pg_isready", "-U", username])
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            try? process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Postgres is ready after \(i) seconds.")
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        throw NSError(domain: "PostgresDockerManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Postgres failed to become ready in time."])
    }
    
    public func runSQLFile(at path: String, dockerPath: String) throws {
        print("📄 Loading SQL file content...")
        let sqlContent = try String(contentsOfFile: path)
        
        let process = createDockerProcess(executable: dockerPath, arguments: ["exec", "-i", containerId!, "psql", "-U", username, "-d", database])
        
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        
        let errPipe = Pipe()
        process.standardError = errPipe
        
        try process.run()
        
        if let data = sqlContent.data(using: .utf8) {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try inputPipe.fileHandleForWriting.close()
        
        process.waitUntilExit()
        
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "PostgresDockerManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to execute SQL file: \(errorOutput)"])
        }
        print("✅ SQL file loaded successfully.")
    }
}
