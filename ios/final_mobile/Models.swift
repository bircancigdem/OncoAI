//
//  Models.swift
//  final_mobile
//
//  Oluşturulma: 2025-08-21
//

import Foundation

// MARK: - Clinician
struct Clinician: Codable {
    let id: String
    let name: String
}

// MARK: - Hasta liste öğesi
// /search uç noktası: { id, fullName, age, stage, ecogScore, cancerType }
struct Patient: Identifiable, Codable, Hashable {
    let id: String          // FastAPI patient_id → String kullanılıyor
    let fullName: String
    let age: Int
    let cancerType: String
    let stage: String
    let ecogScore: Int
}

// MARK: - Klinik özellikler (tablo için)
// /predict JSON’unda "clinical": { pd_l1, tmb, age, metastasis, ecog_score, smoking_status, cancer_stage }
struct Clinical: Codable {
    let pdL1: Double?
    let tmb: Double?
    let age: Int?
    let metastasis: String?
    let ecogScore: Int?
    let smokingStatus: String?
    let cancerStage: String?

    enum CodingKeys: String, CodingKey {
        case pdL1 = "pd_l1"
        case tmb
        case age
        case metastasis
        case ecogScore = "ecog_score"
        case smokingStatus = "smoking_status"
        case cancerStage = "cancer_stage"
    }
}

// MARK: - Tahmin grafiği
// /predict JSON’unda "history": [{ timestamp, success_probability }]
struct PredictionPoint: Identifiable, Codable {
    let id = UUID()
    let timestamp: String
    let successProbability: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case successProbability = "success_probability"
    }
}

// MARK: - Alternatif tedaviler
// /predict JSON’unda "alternatives": [{ treatment, success_probability }]
struct AlternativeProb: Codable, Identifiable {
    var id: String { treatment }
    let treatment: String
    let successProbability: Double

    enum CodingKeys: String, CodingKey {
        case treatment
        case successProbability = "success_probability"
    }
}

// MARK: - Komplikasyon özeti
// /predict JSON’unda "complications_by_treatment": [{ treatment, complication_type, complication_risk_pct }]
struct ComplicationSummary: Codable, Identifiable {
    var id: String { treatment }
    let treatment: String
    let complicationType: String?
    let complicationRiskPct: Double?

    enum CodingKeys: String, CodingKey {
        case treatment
        case complicationType = "complication_type"
        case complicationRiskPct = "complication_risk_pct"
    }
}

// MARK: - /predict cevabı
struct PatientPrediction: Codable {
    let patientId: Int?
    let fullName: String?
    let recommendedTreatment: String?
    let currentProbability: Double?
    let history: [PredictionPoint]?
    let alternatives: [AlternativeProb]?
    let complicationType: String?
    let complicationRiskPct: Double?
    let complicationsByTreatment: [ComplicationSummary]?
    let clinical: Clinical?

    // Kullanımı kolay yardımcılar
    var pid: String { patientId.map(String.init) ?? "?" }
    var recommended: String { recommendedTreatment ?? "-" }
    var currentProb: Double { currentProbability ?? 0.0 }

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case fullName = "full_name"
        case recommendedTreatment = "recommended_treatment"
        case currentProbability = "current_probability"
        case history
        case alternatives
        case complicationType = "complication_type"
        case complicationRiskPct = "complication_risk_pct"
        case complicationsByTreatment = "complications_by_treatment"
        case clinical
    }
}
