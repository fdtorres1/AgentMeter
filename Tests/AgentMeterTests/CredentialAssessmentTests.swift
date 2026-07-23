import XCTest
@testable import AgentMeter

final class CredentialAssessmentTests: XCTestCase {
    // MARK: - OpenRouter

    func testOpenRouterManagementKeyClassification() {
        let facts = OpenRouterProvider.OpenRouterCredentialFacts(
            isManagementKey: true,
            isProvisioningKey: false,
            limit: nil
        )
        let assessment = OpenRouterProvider.assessment(from: facts)
        XCTAssertEqual(assessment.keyTypeLabel, "Management key")
        XCTAssertNil(assessment.upgradeHint)
        XCTAssertEqual(assessment.manageURL, OpenRouterProvider.manageKeysURL)
    }

    func testOpenRouterProvisioningKeyClassification() {
        let facts = OpenRouterProvider.OpenRouterCredentialFacts(
            isManagementKey: false,
            isProvisioningKey: true,
            limit: nil
        )
        let assessment = OpenRouterProvider.assessment(from: facts)
        XCTAssertEqual(assessment.keyTypeLabel, "Management key")
    }

    func testOpenRouterLimitedKeyClassification() {
        let facts = OpenRouterProvider.OpenRouterCredentialFacts(
            isManagementKey: false,
            isProvisioningKey: false,
            limit: 20
        )
        let assessment = OpenRouterProvider.assessment(from: facts)
        XCTAssertEqual(assessment.keyTypeLabel, "Limited key")
        XCTAssertNil(assessment.upgradeHint)
    }

    func testOpenRouterStandardKeyClassification() {
        let facts = OpenRouterProvider.OpenRouterCredentialFacts(
            isManagementKey: false,
            isProvisioningKey: false,
            limit: nil
        )
        let assessment = OpenRouterProvider.assessment(from: facts)
        XCTAssertEqual(assessment.keyTypeLabel, "Standard key")
        XCTAssertNil(assessment.upgradeHint)
    }

    func testOpenRouterKeyResponseDecodesManagementFlags() throws {
        let json = #"{"data":{"limit":null,"is_management_key":true,"is_provisioning_key":false}}"#
        let response = try JSONDecoder().decode(
            OpenRouterProvider.KeyResponse.self,
            from: Data(json.utf8)
        )
        let facts = OpenRouterProvider.OpenRouterCredentialFacts(
            isManagementKey: response.data.isManagementKey ?? false,
            isProvisioningKey: response.data.isProvisioningKey ?? false,
            limit: response.data.limit
        )
        XCTAssertEqual(OpenRouterProvider.assessment(from: facts).keyTypeLabel, "Management key")
    }

    // MARK: - Venice

    func testVeniceAdminKeyAssessment() {
        let assessment = VeniceProvider.assessment(from: .adminKey)
        XCTAssertEqual(assessment.keyTypeLabel, "Admin key")
        XCTAssertNil(assessment.upgradeHint)
        XCTAssertEqual(assessment.manageURL, VeniceProvider.manageKeysURL)
    }

    func testVeniceInferenceKeyAssessment() {
        let assessment = VeniceProvider.assessment(from: .inferenceKey)
        XCTAssertEqual(assessment.keyTypeLabel, "Inference key")
        XCTAssertNotNil(assessment.upgradeHint)
        XCTAssertEqual(assessment.manageURL, VeniceProvider.manageKeysURL)
    }

    func testVeniceBrokenKeyAssessment() {
        let assessment = VeniceProvider.assessment(from: .notWorking)
        XCTAssertEqual(assessment.keyTypeLabel, "Key not working")
        XCTAssertNil(assessment.upgradeHint)
    }

    // MARK: - Z.ai

    func testZaiCodingPlanAssessment() {
        let assessment = ZaiProvider.assessment(from: .codingPlan)
        XCTAssertEqual(assessment.keyTypeLabel, "GLM Coding Plan key")
        XCTAssertNil(assessment.upgradeHint)
        XCTAssertEqual(assessment.manageURL, ZaiProvider.manageKeysURL)
    }

    func testZaiStandardAPIKeyAssessment() {
        let assessment = ZaiProvider.assessment(from: .standardAPIKey)
        XCTAssertEqual(assessment.keyTypeLabel, "Standard API key")
        XCTAssertEqual(
            assessment.summary,
            "Valid key, but Z.ai only exposes usage for GLM Coding Plans"
        )
        XCTAssertNil(assessment.upgradeHint)
    }

    // MARK: - DeepSeek & Moonshot

    func testDeepSeekValidKeyAssessment() {
        let assessment = DeepSeekProvider.assessment(from: .valid)
        XCTAssertEqual(assessment.keyTypeLabel, "Valid key")
        XCTAssertNotNil(assessment.manageURL)
        XCTAssertEqual(assessment.manageURL, DeepSeekProvider.manageKeysURL)
    }

    func testMoonshotValidKeyAssessment() {
        let assessment = MoonshotProvider.assessment(from: .valid)
        XCTAssertEqual(assessment.keyTypeLabel, "Valid key")
        XCTAssertEqual(assessment.manageURL, MoonshotProvider.manageKeysURL)
    }

    func testAllProviderManageURLsAreNonNil() {
        XCTAssertNotNil(OpenRouterProvider.assessment(from: .init(
            isManagementKey: false, isProvisioningKey: false, limit: nil
        )).manageURL)
        XCTAssertNotNil(VeniceProvider.assessment(from: .adminKey).manageURL)
        XCTAssertNotNil(VeniceProvider.assessment(from: .inferenceKey).manageURL)
        XCTAssertNotNil(ZaiProvider.assessment(from: .codingPlan).manageURL)
        XCTAssertNotNil(DeepSeekProvider.assessment(from: .valid).manageURL)
        XCTAssertNotNil(MoonshotProvider.assessment(from: .valid).manageURL)
    }
}
