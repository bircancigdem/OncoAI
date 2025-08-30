// MockAPI.swift
import Foundation

final class MockAPI: APIProtocol {
    static let shared = MockAPI()
    private init() {}

    private let jsonDec: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Auth
    func login(email: String, password: String) async throws -> LoginResponse {
        return LoginResponse(
            access_token: "mock-token-\(UUID().uuidString)",
            token_type: "bearer",
            expires_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(60*60))
        )
    }

    // MARK: - Patients
    func fetchPatients() async throws -> [Patient] {
        return [
            Patient(id: "1", fullName: "Ayşe Yılmaz",  age: 59, cancerType: "NSCLC",    stage: "IIIB", ecogScore: 1),
            Patient(id: "2", fullName: "Mehmet Kaya",  age: 66, cancerType: "Melanoma", stage: "IV",   ecogScore: 0),
        ]
    }

    func searchPatients(byName name: String) async throws -> [Patient] {
        let all = try await fetchPatients()
        let q = name.lowercased()
        return all.filter { $0.fullName.lowercased().contains(q) }
    }

    // MARK: - Prediction
    func fetchPrediction(patientId: Int) async throws -> PatientPrediction {
        return PatientPrediction(
            patientId: patientId,
            fullName: "Mock Hasta",
            recommendedTreatment: "Monotherapy",
            currentProbability: 0.72,
            history: [
                PredictionPoint(timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600)), successProbability: 0.69),
                PredictionPoint(timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)), successProbability: 0.71),
                PredictionPoint(timestamp: ISO8601DateFormatter().string(from: Date()),                         successProbability: 0.72),
            ],
            alternatives: [
                AlternativeProb(treatment: "Chemo_IO", successProbability: 0.65),
                AlternativeProb(treatment: "Other",    successProbability: 0.40),
            ],
            complicationType: "Fatigue",
            complicationRiskPct: 18.5,
            complicationsByTreatment: [
                ComplicationSummary(treatment: "Monotherapy", complicationType: "Rash",        complicationRiskPct: 10.2),
                ComplicationSummary(treatment: "Chemo_IO",    complicationType: "Neutropenia", complicationRiskPct: 22.0),
            ],
            clinical: Clinical(
                pdL1: 35,
                tmb: 8,
                age: 62,
                metastasis: "Yes",
                ecogScore: 1,
                smokingStatus: "Former",
                cancerStage: "IIIB"
            )
        )
    }

    // MARK: - XAI (SHAP)
    func fetchExplain(patientID: String, treatment: String, topK: Int) async throws -> ExplainResponse {
        // Demo/Mock: deterministik birkaç özellik dönelim
        let now = Date()
        _ = now // kullanılmıyor ama istersen timestamp üretirsin

        let features: [TopFeature] = [
            TopFeature(feature: "pd_l1", shap: 0.145, direction: "positive"),
            TopFeature(feature: "tmb", shap: 0.091, direction: "positive"),
            TopFeature(feature: "cat__msi_Stable", shap: -0.072, direction: "negative"),
            TopFeature(feature: "ecog_score", shap: -0.051, direction: "negative"),
            TopFeature(feature: "cat__cancer_stage_IV", shap: -0.044, direction: "negative"),
            TopFeature(feature: "cat__smoking_status_Former", shap: 0.033, direction: "positive"),
        ]

        return ExplainResponse(
            patientID: Int(patientID) ?? 0,
            treatment: treatment,
            probability: 0.72,
            expectedValue: 0.41,
            topFeatures: Array(features.prefix(topK))
        )
    }
}
