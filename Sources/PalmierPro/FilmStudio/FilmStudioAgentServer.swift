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

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private var process: Process?
    private var managedEndpoint: Endpoint?
    private var managedModelID: String?

    func ensureRunning(
        mereRun: URL,
        status: FilmStudioAgentStatus,
        model: FilmStudioAgentModel,
        environment: [String: String]
    ) async throws {
        let endpoint = try endpoint(for: status.provider)

        if await isReady(endpoint, modelID: model.id) {
            return
        }

        if let process, process.isRunning {
            if managedEndpoint == endpoint, managedModelID == model.id {
                try await waitUntilReady(process: process, endpoint: endpoint, modelID: model.id)
                return
            }
            await stop()
        }

        if await isHealthy(endpoint) {
            let servedModels = await loadedModelIDs(endpoint)
            let detail = servedModels.isEmpty ? "no readable model list" : servedModels.joined(separator: ", ")
            throw FilmStudioServiceError.invalidResponse(
                "The configured mere.run provider port \(endpoint.host):\(endpoint.port) is already in use, but it is not serving \(model.id) (reported: \(detail)). Stop or reconfigure that server, then retry."
            )
        }

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
                "Could not start the local mere.run producer server: \(error.localizedDescription)"
            )
        }

        self.process = process
        managedEndpoint = endpoint
        managedModelID = model.id
        do {
            try await waitUntilReady(process: process, endpoint: endpoint, modelID: model.id)
        } catch {
            if self.process === process {
                self.process = nil
                managedEndpoint = nil
                managedModelID = nil
                await terminate(process)
            }
            throw error
        }
    }

    func stop() async {
        guard let process else {
            managedEndpoint = nil
            managedModelID = nil
            return
        }
        self.process = nil
        managedEndpoint = nil
        managedModelID = nil
        await terminate(process)
    }

    private func waitUntilReady(process: Process, endpoint: Endpoint, modelID: String) async throws {
        for _ in 0..<240 {
            try Task.checkCancellation()
            if await isReady(endpoint, modelID: modelID) { return }
            if !process.isRunning {
                throw FilmStudioServiceError.invalidResponse(
                    "The local mere.run producer server exited before it became ready. Open MereRun for runtime details, then retry."
                )
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw FilmStudioServiceError.invalidResponse(
            "The local mere.run producer server did not become ready with \(modelID) on \(endpoint.host):\(endpoint.port)."
        )
    }

    private func isReady(_ endpoint: Endpoint, modelID: String) async -> Bool {
        guard await isHealthy(endpoint) else { return false }
        return await loadedModelIDs(endpoint).contains(modelID)
    }

    private func isHealthy(_ endpoint: Endpoint) async -> Bool {
        guard let url = url(endpoint, path: "/health") else { return false }
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

    private func loadedModelIDs(_ endpoint: Endpoint) async -> [String] {
        guard let url = url(endpoint, path: "/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.75
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let models = try? JSONDecoder().decode(ModelsResponse.self, from: data) else { return [] }
            return models.data.map(\.id)
        } catch {
            return []
        }
    }

    private func url(_ endpoint: Endpoint, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = path
        return components.url
    }

    private func endpoint(for provider: FilmStudioAgentProvider) throws -> Endpoint {
        let rawHost = provider.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = normalizedLoopbackHost(rawHost?.isEmpty == false ? rawHost! : "127.0.0.1")
        guard let host else {
            throw FilmStudioServiceError.invalidResponse(
                "Palmier will only auto-start the GRACE producer server on loopback. Configure the Pi provider for localhost, 127.0.0.1, or ::1."
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
            for _ in 0..<10 {
                if !process.isRunning { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
