import Testing
@testable import PalmierPro

@Suite("Film Studio agent selection")
struct FilmStudioAgentSelectorTests {
    @Test
    func recommendedInstalledModelWins() {
        let status = makeStatus(
            memoryGB: 24,
            recommendedModelID: "recommended",
            models: [
                makeModel(id: "recommended", minimumGB: 16, recommendedGB: 24),
                makeModel(id: "larger", minimumGB: 16, recommendedGB: 64),
            ]
        )

        #expect(FilmStudioAgentSelector.select(from: status)?.id == "recommended")
    }

    @Test
    func fallbackUsesLargestInstalledModelThatFitsThisMac() {
        let status = makeStatus(
            memoryGB: 24,
            recommendedModelID: "missing",
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
        let status = makeStatus(
            memoryGB: 24,
            recommendedModelID: "not-installed",
            models: [
                makeModel(id: "not-installed", minimumGB: 8, recommendedGB: 12, installed: false),
                makeModel(id: "not-startable", minimumGB: 8, recommendedGB: 12, startable: false),
                makeModel(id: "too-large", minimumGB: 32, recommendedGB: 64),
            ]
        )

        #expect(FilmStudioAgentSelector.select(from: status) == nil)
    }

    private func makeStatus(
        memoryGB: Int,
        recommendedModelID: String?,
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
