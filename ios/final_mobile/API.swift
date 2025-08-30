// API.swift
import Foundation

final class API: APIProtocol {

    // MARK: - Config
    private var baseURL: URL {
        URL(string: Config.apiBaseURL)!   // Örn: "http://127.0.0.1:8000"
    }

    // Uygulama boyunca kullanacağımız bearer token
    static var authToken: String?

    // Decoder
    private let jsonDec: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Yardımcı
    private func makeRequest(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        needsAuth: Bool = true
    ) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if needsAuth, let tok = API.authToken, !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - Auth
    func login(email: String, password: String) async throws -> LoginResponse {
        struct LoginIn: Encodable { let email: String; let password: String }
        let payload = LoginIn(email: email, password: password)
        let data = try JSONEncoder().encode(payload)

        var req = try makeRequest(path: "/auth/login", method: "POST", body: data, needsAuth: false)

        let (respData, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: respData, encoding: .utf8) ?? "<non-utf8 \(respData.count)B>"
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }

        let result = try jsonDec.decode(LoginResponse.self, from: respData)
        API.authToken = result.access_token
        return result
    }

    // MARK: - Patients
    func fetchPatients() async throws -> [Patient] {
        return try await searchPatients(byName: "a")
    }

    func searchPatients(byName name: String) async throws -> [Patient] {
        let req = try makeRequest(
            path: "/search",
            query: [URLQueryItem(name: "name", value: name)],
            needsAuth: true
        )
        let (data, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count)B>"
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }

        struct RawPatient: Decodable {
            let id: Int
            let fullName: String
            let age: Int
            let stage: String
            let ecogScore: Int
            let cancerType: String?
        }

        let arr = try jsonDec.decode([RawPatient].self, from: data)
        return arr.map {
            Patient(id: String($0.id),
                    fullName: $0.fullName,
                    age: $0.age,
                    cancerType: $0.cancerType ?? "",
                    stage: $0.stage,
                    ecogScore: $0.ecogScore)
        }
    }

    // MARK: - Prediction
    func fetchPrediction(patientId: Int) async throws -> PatientPrediction {
        let req = try makeRequest(
            path: "/predict",
            query: [URLQueryItem(name: "patient_id", value: String(patientId))],
            needsAuth: true
        )
        let (data, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count)B>"
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }

        return try jsonDec.decode(PatientPrediction.self, from: data)
    }

    // MARK: - XAI (SHAP)
    func fetchExplain(patientID: String, treatment: String, topK: Int) async throws -> ExplainResponse {
        let req = try makeRequest(
            path: "/explain",
            query: [
                URLQueryItem(name: "patient_id", value: patientID),      // backend int'e çeviriyor
                URLQueryItem(name: "treatment", value: treatment),
                URLQueryItem(name: "top_k", value: String(topK))
            ],
            needsAuth: true
        )
        let (data, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count)B>"
            throw APIError.httpStatus(code: http.statusCode, body: body)
        }

        return try jsonDec.decode(ExplainResponse.self, from: data)
    }
}

// Tek (ve ortak) API hatası enum’u — başka dosyada zaten varsa BUNU ekleme.
enum APIError: LocalizedError {
    case httpStatus(code: Int, body: String)
    var errorDescription: String? {
        switch self {
        case .httpStatus(let c, let b): return "HTTP \(c): \(b)"
        }
    }
}
