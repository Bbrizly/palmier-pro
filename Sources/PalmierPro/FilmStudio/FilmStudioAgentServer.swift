import Darwin
import Foundation

actor FilmStudioAgentServer {
    static let shared = FilmStudioAgentServer()

    private struct Endpoint: Equatable, Sendable {
        let host: String
        let port: Int
    }

    private struct HealthResponse: Decodable {
        let status: String
    }

    private var process: Process?
    private var managedEndpoint: Endpoint?

    func ensureRunning(
        mereRun: URL,
        status: FilmStudioAgentStatus,
        model: FilmStudioAgentModel,
        environment: [String: String]
    ) async throws {
        let endpoint = try endpoint(for: status.provider)
        if await isHealthy(endpoint) { return }

        if let process, process.isRunning, managedEndpoint == endpoint {
            try await waitUntilHealthy(process: process, endpoint: endpoint)
            return
        }

        await stop()

        let process = Process()
        process.executableURL = mereRun
        process.arguments = [
            "api", "serve",
            "--engine", model.servingEngine,
            "--model", model.id,
            "--host", endpoint.host,
            "--port", String(endpoint.port),
        ]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw FilmStudioServiceError.invalidResponse(
                "Could not start the local mere.run agent server: \(error.localizedDescription)"
            )
        }

        self.process = process
        managedEndpoint = endpoint
        do {
            try await waitUntilHealthy(process: process, endpoint: endpoint)
        } catch {
            if self.process === process {
                stopManagedProcess()
            }
            throw error
        }
    }

    func stop() async {
        guard let process else {
            managedEndpoint = nil
            return
        }
        self.process = nil
        managedEndpoint = nil
        await terminate(process)
    }

    private func waitUntilHealthy(process: Process, endpoint: Endpoint) async throws {
        for _ in 0..<240 {
            try Task.checkCancellation()
            if await isHealthy(endpoint) { return }
            if !process.isRunning {
                throw FilmStudioServiceError.invalidResponse(
                    "The local mere.run agent server exited before it became ready. Open MereRun for runtime details, then retry."
                )
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw FilmStudioServiceError.invalidResponse(
            "The local mere.run agent server did not become ready on \(endpoint.host):\(endpoint.port)."
        )
    }

    private func isHealthy(_ endpoint: Endpoint) async -> Bool {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/health"
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.75
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let health = try? JSONDecoder().decode(HealthResponse.self, from: data) else { return false }
            return health.status == "ok"
        } catch {
            return false
        }
    }

    private func endpoint(for provider: FilmStudioAgentProvider) throws -> Endpoint {
        let rawHost = provider.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = normalizedLoopbackHost(rawHost?.isEmpty == false ? rawHost! : "127.0.0.1")
        guard let host else {
            throw FilmStudioServiceError.invalidResponse(
                "Palmier will only auto-start the GRACE agent server on loopback. Configure the Pi provider for localhost or 127.0.0.1."
            )
        }
        let port = provider.port ?? 8080
        guard (1...65_535).contains(port) else {
            throw FilmStudioServiceError.invalidResponse("The configured mere.run provider port is invalid: \(port).")
        }
        return Endpoint(host: host, port: port)
    }

    private func normalizedLoopbackHost(_ host: String) -> String? {
        let normalized = host.lowercased()
        if normalized == "localhost" { return "127.0.0.1" }
        if normalized == "::1" || normalized == "[::1]" { return "::1" }
        if normalized.hasPrefix("127.") { return normalized }
        return nil
    }

    private func terminate(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 {
            if !process.isRunning { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private func stopManagedProcess() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        managedEndpoint = nil
    }
}
