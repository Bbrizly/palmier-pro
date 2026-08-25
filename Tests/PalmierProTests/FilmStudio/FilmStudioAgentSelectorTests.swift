import Testing
@testable import PalmierPro

@Suite("Film Studio runtime readiness")
struct FilmStudioRuntimeReadinessTests {
    @Test
    func recommendedInstalledModelWins() {
        let status = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: "recommended",
            providerModelID: "recommended",
            models: [
                makeModel(id: "recommended", minimumGB: 16, recommendedGB: 24),
                makeModel(id: "larger", minimumGB: 16, recommendedGB: 64),
            ]
        )

        #expect(FilmStudioAgentSelector.select(from: status)?.id == "recommended")
    }

    @Test
    func fallbackUsesLargestInstalledModelThatFitsThisMac() {
        let status = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: "missing",
            providerModelID: nil,
            models: [
                makeModel(id: "small", minimumGB: 8, recommendedGB: 12),
                makeModel(id: "fit", minimumGB: 16, recommendedGB: 24),
                makeModel(id: "too-large", minimumGB: 32, recommendedGB: 64),
            ]
        )

        #expect(FilmStudioAgentSelector.select(from: status)?.id == "fit")
    }

    @Test
    func unavailableModelsAreNeverSelected() {
        let status = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: "not-installed",
            providerModelID: nil,
            models: [
                makeModel(id: "not-installed", minimumGB: 8, recommendedGB: 12, installed: false),
                makeModel(id: "not-startable", minimumGB: 8, recommendedGB: 12, startable: false),
                makeModel(id: "too-large", minimumGB: 32, recommendedGB: 64),
            ]
        )

        #expect(FilmStudioAgentSelector.select(from: status) == nil)
    }

    @Test
    func planningDoesNotRequireAgentOrMediaRuntime() {
        let runtime = makeRuntime(
            agentStatus: nil,
            selectedModel: nil,
            doctor: nil
        )

        #expect(runtime.planningReady)
        #expect(!runtime.agentReady)
        #expect(!runtime.productionReady)
    }

    @Test
    func agentReadinessRequiresProviderForSelectedModel() {
        let selected = makeModel(id: "agent", minimumGB: 8, recommendedGB: 16)
        let wrongProvider = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: selected.id,
            providerModelID: "different-model",
            models: [selected]
        )
        let rightProvider = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: selected.id,
            providerModelID: selected.id,
            models: [selected]
        )

        #expect(!makeRuntime(agentStatus: wrongProvider, selectedModel: selected, doctor: readyDoctor()).agentReady)
        #expect(makeRuntime(agentStatus: rightProvider, selectedModel: selected, doctor: readyDoctor()).agentReady)
    }

    @Test
    func productionReadinessAddsMediaTools() {
        let selected = makeModel(id: "agent", minimumGB: 8, recommendedGB: 16)
        let status = makeAgentStatus(
            memoryGB: 24,
            recommendedModelID: selected.id,
            providerModelID: selected.id,
            models: [selected]
        )
        let missingFFmpeg = FilmStudioDoctorReport(
            ok: false,
            checks: [
                .init(name: "pi", ok: true, required: true, detail: "/tmp/pi"),
                .init(name: "mere.run", ok: true, required: true, detail: "/tmp/mere.run"),
                .init(name: "ffmpeg", ok: false, required: true, detail: "not found"),
                .init(name: "ffprobe", ok: true, required: true, detail: "/tmp/ffprobe"),
            ],
            note: nil
        )

        #expect(makeRuntime(agentStatus: status, selectedModel: selected, doctor: missingFFmpeg).agentReady)
        #expect(!makeRuntime(agentStatus: status, selectedModel: selected, doctor: missingFFmpeg).productionReady)
        #expect(makeRuntime(agentStatus: status, selectedModel: selected, doctor: readyDoctor()).productionReady)
    }

    private func makeRuntime(
        agentStatus: FilmStudioAgentStatus?,
        selectedModel: FilmStudioAgentModel?,
        doctor: FilmStudioDoctorReport?
    ) -> FilmStudioRuntimeStatus {
        FilmStudioRuntimeStatus(
            mereRunPath: "/tmp/mere.run",
            filmToolPath: "/tmp/mere-film-tools",
            agentStatus: agentStatus,
            selectedAgentModel: selectedModel,
            doctor: doctor,
            mereRunError: nil,
            filmToolError: nil,
            agentError: nil,
            doctorError: nil
        )
    }

    private func readyDoctor() -> FilmStudioDoctorReport {
        FilmStudioDoctorReport(
            ok: true,
            checks: [
                .init(name: "pi", ok: true, required: true, detail: "/tmp/pi"),
                .init(name: "mere.run", ok: true, required: true, detail: "/tmp/mere.run"),
                .init(name: "ffmpeg", ok: true, required: true, detail: "/tmp/ffmpeg"),
                .init(name: "ffprobe", ok: true, required: true, detail: "/tmp/ffprobe"),
            ],
            note: nil
        )
    }

    private func makeAgentStatus(
        memoryGB: Int,
        recommendedModelID: String?,
        providerModelID: String?,
        models: [FilmStudioAgentModel]
    ) -> FilmStudioAgentStatus {
        FilmStudioAgentStatus(
            machine: FilmStudioAgentMachine(
                processor: "Apple Silicon",
                unifiedMemoryGB: memoryGB,
                appleSiliconMac: true,
                linux: false
            ),
            pi: FilmStudioAgentPi(
                installed: true,
                managedInstall: true,
                autoInstallSupported: true,
                path: "/tmp/pi",
                version: "1"
            ),
            provider: FilmStudioAgentProvider(
                configured: providerModelID != nil,
                host: "127.0.0.1",
                port: 8080,
                modelID: providerModelID
            ),
            recommendedModelID: recommendedModelID,
            models: models
        )
    }

    private func makeModel(
        id: String,
        minimumGB: Int,
        recommendedGB: Int,
        installed: Bool = true,
        startable: Bool = true
    ) -> FilmStudioAgentModel {
        FilmStudioAgentModel(
            id: id,
            displayName: id,
            summary: "",
            minimumUnifiedMemoryGB: minimumGB,
            recommendedUnifiedMemoryGB: recommendedGB,
            servingEngine: "test",
            startableByMereRun: startable,
            sourceConfigurationRequired: false,
            installed: installed,
            reason: nil
        )
    }
}
