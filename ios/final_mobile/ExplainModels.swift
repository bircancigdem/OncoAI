// ExplainModels.swift
import Foundation

struct ExplainResponse: Codable {
    let patientID: Int
    let treatment: String
    let probability: Double
    let expectedValue: Double?
    let topFeatures: [TopFeature]

    enum CodingKeys: String, CodingKey {
        case patientID = "patient_id"
        case treatment
        case probability
        case expectedValue = "expected_value"
        case topFeatures = "top_features"
    }
}

struct TopFeature: Codable, Identifiable {
    var id: String { feature }
    let feature: String
    let shap: Double
    let direction: String?
}
