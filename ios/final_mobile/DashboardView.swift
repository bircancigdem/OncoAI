// DashboardView.swift
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Dashboard Root
struct DashboardView: View {
    var body: some View {
        NavigationSplitView {
            PatientListView()
        } detail: {
            DetailSection()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LogoutButton()
            }
        }
    }
}

// MARK: - Patient List
private struct PatientListView: View {
    @EnvironmentObject var auth: AuthVM

    var body: some View {
        List(auth.patients) { p in
            VStack(alignment: .leading, spacing: 4) {
                Text(p.fullName).font(.headline)
                Text("\(p.cancerType) • \(p.stage) • ECOG \(p.ecogScore)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await auth.select(p) } }
        }
        .overlay { if auth.isLoading { ProgressView("Aranıyor...") } }
        .navigationTitle("Hastalar")
        .task { await auth.load() }
        .searchable(
            text: Binding(
                get: { auth.searchText },
                set: { auth.searchText = $0 }
            ),
            prompt: "Hasta adı ara"
        )
        .onSubmit(of: .search) {
            Task { await auth.search(name: auth.searchText) }
        }
        .task(id: auth.searchText) {
            try? await Task.sleep(nanoseconds: 400_000_000) // küçük debounce
            await auth.search(name: auth.searchText)
        }
    }
}

// MARK: - Detail + XAI
private struct DetailSection: View {
    @EnvironmentObject var auth: AuthVM

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = auth.selected {
                    Text(p.fullName)
                        .font(.system(size: 32, weight: .bold))
                        .padding(.bottom, 4)

                    Text("Yaş: \(p.age) • \(p.cancerType) • \(p.stage) • ECOG \(p.ecogScore)")
                        .foregroundColor(.secondary)

                    if let pred = auth.prediction, let c = pred.clinical {
                        GroupBox("Klinik Veriler") {
                            VStack(alignment: .leading, spacing: 8) {
                                Row("PD-L1", value: c.pdL1.map { String(format: "%.1f", $0) } ?? "-")
                                Row("TMB", value: c.tmb.map { String(format: "%.1f", $0) } ?? "-")
                                Row("Yaş", value: c.age.map(String.init) ?? "-")
                                Row("Metastasis", value: c.metastasis ?? "-")
                                Row("ECOG", value: c.ecogScore.map(String.init) ?? "-")
                                Row("Sigara", value: c.smokingStatus ?? "-")
                                Row("Evre", value: c.cancerStage ?? "-")
                            }
                            .padding(.top, 4)
                        }
                    }

                    if let pred = auth.prediction {
                        GroupBox("Tedavi Önerisi") {
                            HStack(spacing: 16) {
                                Text("Öneri: ").bold() + Text(pred.recommended)
                                Text(String(format: "Başarı: %.1f%%", pred.currentProb * 100)).bold()
                            }
                        }

                        if let ctype = pred.complicationType,
                           let risk = pred.complicationRiskPct {
                            GroupBox("Komplikasyon") {
                                Text("\(ctype)  •  Risk: \(String(format: "%.1f", risk))%")
                                    .padding(.vertical, 2)
                            }
                        }

                        if let alts = pred.alternatives, !alts.isEmpty {
                            GroupBox("Alternatif Tedaviler") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(alts) { a in
                                        Text("• \(a.treatment): \(String(format: "%.1f", a.successProbability * 100))%")
                                    }
                                }
                            }
                        }

                        // ✅ XAI (SHAP) — Önerilen tedavi için açıklama
                        GroupBox("Açıklama (XAI - SHAP)") {
                            ExplanationView(
                                patientID: p.id,                // String id
                                treatment: pred.recommended     // backend'e "treatment"
                            )
                            .environmentObject(auth)           // 🔗 alt görünüme auth’u geçir
                        }

                        if let hist = pred.history, !hist.isEmpty {
                            Chart(hist) { pt in
                                LineMark(
                                    x: .value("Zaman", pt.timestamp),
                                    y: .value("Başarı", pt.successProbability * 100)
                                )
                                PointMark(
                                    x: .value("Zaman", pt.timestamp),
                                    y: .value("Başarı", pt.successProbability * 100)
                                )
                            }
                            .chartYScale(domain: 0...100)
                            .frame(height: 300)
                            .padding(.top, 6)
                        } else {
                            Text("Grafik için geçmiş veri yok.")
                                .foregroundColor(.secondary)
                        }
                    } else if auth.isLoadingPrediction {
                        ProgressView("Tahmin getiriliyor…")
                    } else {
                        Text("Bir hata seçtiğinizde tahmin otomatik yüklenecek.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Soldan bir hasta seçin veya arayın.")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(auth.selected?.fullName ?? "Detay")
        .navigationBarTitleDisplayMode(.inline)
    }
}





// MARK: - XAI Explanation View (2 sütun grid, dedup + daha fazla çekip 8'e indir)
private struct ExplanationView: View {
    @EnvironmentObject var auth: AuthVM

    let patientID: String
    let treatment: String
    var topK: Int = 8   // kartta göstermek istediğin kesin sayı

    @State private var loading = false
    @State private var errorText: String?
    @State private var explain: ExplainResponse?

    // 2 sütun
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    // Bilinen kategorik base'ler (OHE)
    private let catBases: [String: String] = [
        "msi": "MSI",
        "metastasis": "Metastaz",
        "smoking_status": "Sigara",
        "cancer_stage": "Evre",
        "io_group": "Tedavi"
    ]

    // Bilinen sayısal base'ler
    private let numLabels: [String: String] = [
        "pd_l1": "PD-L1",
        "tmb": "TMB",
        "age": "Yaş",
        "ecog_score": "ECOG",
        "treatment_start_days": "Tedavi Başl. Gün"
    ]

    struct DisplayFeature: Identifiable {
        let id = UUID()
        let baseKey: String          // Örn. cancer_stage
        let label: String            // Örn. Evre
        let valueText: String?       // Örn. IV / Former
        let shap: Double
        let direction: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                ProgressView("Açıklama hesaplanıyor…")

            } else if let err = errorText {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                    Button("Tekrar dene") { Task { await fetchExplain() } }
                }
                .foregroundColor(.orange)

            } else if let ex = explain {
                // Başlık altı kısa özet
                HStack(spacing: 16) {
                    Text(String(format: "Olasılık: %.1f%%", ex.probability * 100)).bold()
                    if let ev = ex.expectedValue {
                        Text(String(format: "Beklenen Değer: %.3f", ev))
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }

                // Normalize + dedup edilmiş liste → en çok etki eden topK
                let allMapped = normalizedDedup(ex.topFeatures)
                let items = Array(allMapped.prefix(topK))   // burada her zaman 8’e düşürmeye çalışıyoruz

                if items.isEmpty {
                    Text("Öne çıkan özellik bulunamadı.")
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(items) { f in
                            VStack(alignment: .leading, spacing: 6) {
                                // Başlık: "Evre" / "Sigara" / "PD-L1" vb.
                                Text(f.label)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                // Değer varsa (kategori) göster
                                if let v = f.valueText, !v.isEmpty {
                                    Text(v)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }

                                // SHAP değeri
                                Text(String(format: "%+.4f", f.shap))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(colorFor(direction: f.direction))

                                // Yön etiketi (opsiyonel)
                                if let dir = f.direction {
                                    Text(dir == "negative" ? "Negatif katkı" : "Pozitif katkı")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill((f.direction == "negative" ? Color.red.opacity(0.08) : Color.green.opacity(0.08)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke((f.direction == "negative" ? Color.red.opacity(0.25) : Color.green.opacity(0.25)), lineWidth: 0.8)
                            )
                        }
                    }
                }

            } else {
                Text("Açıklama yok.")
                    .foregroundColor(.secondary)
            }
        }
        .task(id: taskKey) { await fetchExplain() }
    }

    // Hasta/tedavi değişince yeniden yükle
    private var taskKey: String { "\(patientID)#\(treatment)#\(topK)" }

    private func fetchExplain() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            // Ham özellikleri bol çek → dedup sonra topK’a indir
            let requestTopK = min(50, max(16, topK * 4)) // 8 istiyorsak 32; tavan 50
            let ex = try await auth.fetchExplain(
                patientID: patientID,
                treatment: treatment,
                topK: requestTopK
            )
            self.explain = ex
        } catch {
            self.errorText = error.localizedDescription
        }
    }

    // --- Normalizasyon + Duplicate önleme ---
    private func normalizedDedup(_ feats: [TopFeature]) -> [DisplayFeature] {
        // 1) Her SHAP özelliğini (OHE/sayısal) DisplayFeature’a çevir
        let mapped: [DisplayFeature] = feats.compactMap { tf in
            parseFeature(tf)
        }

        // 2) Aynı baseKey için (örn. cancer_stage) birden fazla satır varsa
        //    en büyük |SHAP| olanı seç → duplicate gider
        var bestByBase: [String: DisplayFeature] = [:]
        for d in mapped {
            if let cur = bestByBase[d.baseKey] {
                if abs(d.shap) > abs(cur.shap) {
                    bestByBase[d.baseKey] = d
                }
            } else {
                bestByBase[d.baseKey] = d
            }
        }

        // 3) |SHAP| azalan sıraya koy
        let unique = Array(bestByBase.values)
        return unique.sorted { abs($0.shap) > abs($1.shap) }
    }

    // Tek bir TopFeature’ı sağlam şekilde ayrıştır
    private func parseFeature(_ f: TopFeature) -> DisplayFeature? {
        let name = f.feature

        // 1) OHE (cat__)
        if name.hasPrefix("cat__") {
            let rest = String(name.dropFirst("cat__".count))
            // Bilinen base’lerle eşleşme: en uzun prefix’i seç
            if let baseKey = catBases.keys.sorted(by: { $0.count > $1.count }).first(where: { rest.hasPrefix($0 + "_") || rest == $0 }) {
                let label = catBases[baseKey] ?? baseKey.capitalized

                var value = ""
                if rest == baseKey {
                    value = "" // kategori yoksa
                } else {
                    // baseKey + '_' sonrası kategoriyi al
                    value = String(rest.dropFirst(baseKey.count + 1))
                    value = value.replacingOccurrences(of: "_", with: " ")
                    value = value.replacingOccurrences(of: "-", with: " ")
                    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // "Stage IV" → "IV" sadeleştirme (istenirse)
                if baseKey == "cancer_stage" {
                    value = value.replacingOccurrences(of: "Stage ", with: "")
                }

                return DisplayFeature(
                    baseKey: baseKey,
                    label: label,
                    valueText: value,
                    shap: f.shap,
                    direction: f.direction
                )
            }

            // Bilinmeyen cat__ ise en azından okunur hale getir
            let parts = rest.split(separator: "_", maxSplits: 1).map(String.init)
            let base = parts.first ?? rest
            let value = parts.count > 1 ? parts[1].replacingOccurrences(of: "_", with: " ") : ""
            let label = catBases[base] ?? base.replacingOccurrences(of: "_", with: " ").capitalized

            return DisplayFeature(
                baseKey: base,
                label: label,
                valueText: value,
                shap: f.shap,
                direction: f.direction
            )
        }

        // 2) Sayısal (num__)
        if name.hasPrefix("num__") {
            let base = String(name.dropFirst("num__".count))
            let label = numLabels[base] ?? prettify(base)
            return DisplayFeature(
                baseKey: base,
                label: label,
                valueText: nil,
                shap: f.shap,
                direction: f.direction
            )
        }

        // 3) Düz isim
        let base = name
        let label = numLabels[base] ?? catBases[base] ?? prettify(base)
        return DisplayFeature(
            baseKey: base,
            label: label,
            valueText: nil,
            shap: f.shap,
            direction: f.direction
        )
    }

    private func prettify(_ raw: String) -> String {
        switch raw {
        case "pd_l1": return "PD-L1"
        case "tmb": return "TMB"
        case "age": return "Yaş"
        case "ecog_score": return "ECOG"
        case "treatment_start_days": return "Tedavi Başl. Gün"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func colorFor(direction: String?) -> Color {
        (direction == "negative") ? .red : .green
    }
}
// MARK: - Chips & Wrap
private struct ShapChip: View {
    let feature: String
    let shap: Double
    let direction: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: direction == "negative" ? "arrow.down.right" : "arrow.up.right")
            Text(feature).lineLimit(1)
            Text(String(format: "%+.3f", shap))
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(direction == "negative" ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
        .foregroundColor(direction == "negative" ? .red : .green)
        .clipShape(Capsule())
    }
}

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        FlexibleView(
            availableWidth: UIScreen.main.bounds.width - 64,
            spacing: spacing,
            lineSpacing: lineSpacing,
            content: { content }
        )
    }
}

private struct FlexibleView<Content: View>: View {
    let availableWidth: CGFloat
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: () -> Content

    init(availableWidth: CGFloat,
         spacing: CGFloat,
         lineSpacing: CGFloat,
         @ViewBuilder content: @escaping () -> Content) {
        self.availableWidth = availableWidth
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        GeometryReader { _ in
            self.generateContent()
        }
        .frame(minHeight: 0)
    }

    private func generateContent() -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            content()
                .alignmentGuide(.leading) { d in
                    if abs(width - d.width) > availableWidth {
                        width = 0
                        height -= d.height + lineSpacing
                    }
                    let res = width
                    width -= d.width + spacing
                    return res
                }
                .alignmentGuide(.top) { _ in height }
        }
    }
}

// MARK: - Logout + Row
private struct LogoutButton: View {
    @EnvironmentObject var auth: AuthVM
    var body: some View { Button("Çıkış") { auth.logout() } }
}

private struct Row: View {
    let label: String
    let value: String
    init(_ label: String, value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}
