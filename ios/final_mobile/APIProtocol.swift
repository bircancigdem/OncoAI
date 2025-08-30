// APIProtocol.swift
import Foundation

protocol APIProtocol {
    // Auth
    func login(email: String, password: String) async throws -> LoginResponse

    // Patients
    func fetchPatients() async throws -> [Patient]
    func searchPatients(byName name: String) async throws -> [Patient]

    // Prediction
    func fetchPrediction(patientId: Int) async throws -> PatientPrediction

    // XAI (SHAP)
    func fetchExplain(patientID: String, treatment: String, topK: Int) async throws -> ExplainResponse


}
