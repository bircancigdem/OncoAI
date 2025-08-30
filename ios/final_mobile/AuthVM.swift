// AuthVM.swift
import Foundation

@MainActor
final class AuthVM: ObservableObject {
    // Auth
    @Published var isAuthenticated = false
    @Published var error: String?

    // UI / Data
    @Published var patients: [Patient] = []
    @Published var selected: Patient?
    @Published var prediction: PatientPrediction?
    @Published var isLoading = false
    @Published var isLoadingPrediction = false

    // 🔎 Search alanı (DashboardView.searchable bunu kullanıyor)
    @Published var searchText: String = ""

    // ✅ Gerçek API
    private let api: APIProtocol = API()      // Mock kullanmak istersen: MockAPI.shared

    // MARK: - Auth
    func login(email: String, password: String) async {
        error = nil
        do {
            _ = try await api.login(email: email, password: password)
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            self.error = "Giriş başarısız: \(error.localizedDescription)"
        }
    }

    func logout() {
        isAuthenticated = false
        error = nil
        patients = []
        selected = nil
        prediction = nil
        searchText = ""
        TokenStore.shared.clear()
    }

    // MARK: - Initial load (DashboardView .task çağırıyor)
    func load() async {
        // İstersen burada son aramayı/önerilenleri çekebilirsin.
        // Şimdilik sadece başlangıç durumunu temiz tutalım.
        error = nil
    }

    // MARK: - Search & Selection
    func search(name: String) async {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            patients = []
            selected = nil
            prediction = nil
            error = nil
            return
        }
        isLoading = true
        error = nil
        do {
            let result = try await api.searchPatients(byName: q)
            patients = result
            selected = nil
            prediction = nil
        } catch {
            self.error = "Arama başarısız: \(error.localizedDescription)"
            patients = []
            selected = nil
            prediction = nil
        }
        isLoading = false
    }

    func select(_ p: Patient) async {
        selected = p
        await loadPrediction()
    }

    // MARK: - Prediction
    func loadPrediction() async {
        guard let sel = selected, let pid = Int(sel.id) else { return }
        isLoadingPrediction = true
        error = nil
        do {
            let r = try await api.fetchPrediction(patientId: pid)
            prediction = r
        } catch {
            self.error = "Tahmin alınamadı: \(error.localizedDescription)"
            prediction = nil
        }
        isLoadingPrediction = false
    }
    // MARK: - XAI (SHAP Explanation)
    func fetchExplain(patientID: String, treatment: String, topK: Int = 8) async throws -> ExplainResponse {
        return try await api.fetchExplain(patientID: patientID, treatment: treatment, topK: topK)
    }
}
