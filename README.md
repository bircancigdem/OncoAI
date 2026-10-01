OncoAI — Akciğer Adenokarsinomunda İmmünoterapi için Açıklanabilir Klinik Karar Destek Sistemi


Küçük hücreli dışı akciğer kanseri (akciğer adenokarsinomu) hastalarında immünoterapiye yanıtı ve komplikasyon riskini öngören ve sonuçları bir iOS uygulaması aracılığıyla hekimlere sunan, uçtan uca, açıklanabilir bir yapay zeka sistemi.


🏆 TEKNOFEST 2025 Finalisti — Onkoloji 3T Yarışması (İlk 10, En İyi Sunum Ödülü)

📺 Demo video: https://youtu.be/8lFrWBBPf3Y

Genel Bakış

İmmün kontrol noktası inhibitörleri (örn. pembrolizumab, nivolumab), ilerlemiş NSCLC’de sağkalımı iyileştirmiştir; ancak hastaların yalnızca %20–30’u tedaviye yanıt vermektedir ve tedaviye yanıt vermeyen hastalar hâlâ ciddi immün kaynaklı yan etkilere maruz kalmaktadır. OncoAI, onkologların tedavi öncesinde iki soruyu yanıtlamasına yardımcı olan bir klinik karar destek sistemidir (CDSS):


Bu hastanın immünoterapiye yanıt verme olasılığı ne kadardır?
Hangi komplikasyonlar ortaya çıkabilir ve bunların ortaya çıkma olasılığı nedir?


En önemlisi, her tahmin açıklanabilir niteliktedir: Doktorlar, modelin sadece sonucunu değil, bu sonuca nasıl ulaştığını da görebilirler. Sistem bir karar destek aracıdır — doktorlara destek olur, onların yerini almaz.


Temel Özellikler

Entegre klinik ve moleküler belirteçlerden (ECOG, evre, yaş, sigara kullanım öyküsü, PD-L1, TMB, MSI, metastaz) immünoterapi yanıtının öngörülmesi.
Açıklanabilir Yapay Zeka (XAI): Her bir tahmini hangi özelliklerin etkilediğine dair hasta bazında açıklamalar.
Bulanık mantık komplikasyon risk puanlaması: Klinik belirsizliği (sınırda ECOG, yaş, PD-L1 aralıkları) yorumlanabilir sayısal risk puanlarına dönüştürür.
İki aşamalı komplikasyon modellemesi: çok sınıflı bir model komplikasyon türünü tahmin eder, regresyon modeli ise olasılığını hesaplar.
Hekimler için iOS uygulaması: doktorlar bir hastanın adına dokunarak tahmin, risk, alternatifler ve açıklamaları anında görebilir.
Güvenlik öncelikli mimari: uçtan uca şifreleme, cihaz üzerinde işleme ve KVKK / HIPAA ilkeleriyle uyumlu rol tabanlı erişim.


Teknoloji Yığını Makine Öğrenimi / Veri

Python, pandas, NumPy, scikit-learn
XGBoost, Random Forest, LightGBM, Karar Ağacı, SVM (en iyi performans için karşılaştırıldı)
Sentetik veri artırımı ve sınıf dengeleme için CTGAN ve SMOTE
Olasılık kalibrasyonu için izotonik regresyon
Analiz ve görselleştirme için Matplotlib / Seaborn


Açıklanabilirlik
SHAP, LIME, ELI5 (özellik önemi + hasta bazında yerel açıklamalar)
Bulanık mantık (klinik risk puanlaması için üyelik fonksiyonları)


Arka Uç
FastAPI, Docker, MongoDB
JWT kimlik doğrulama, AES-GCM uçtan uca şifreleme, uç bilgi işlem


Mobil
SwiftUI (iOS) — hekimlere yönelik arayüz

Sonuç
Metric	Best Model (XGBoost)
Accuracy	93%
ROC-AUC	97%

Çeşitli algoritmalar (XGBoost, Random Forest, LightGBM, Karar Ağacı, SVM) eğitildi ve karşılaştırıldı; XGBoost, immünoterapi yanıtının tahmininde en iyi performansı gösterdi. Olasılık sonuçları, klinik güvenilirlik açısından izotonik regresyon ile kalibre edildi.

Nasıl Çalışıyor?

Klinik ve moleküler veriler (ECOG, evre, yaş, sigara kullanımı, PD-L1, TMB, MSI, metastaz)
│
▼
Makine öğrenimi modelleri (XGBoost / RF / LightGBM / SVM) ──► immünoterapiye yanıt olasılığı
│
▼
XAI modülü (SHAP / LIME / ELI5) ──► hasta başına açıklama
│
▼
Bulanık mantık modülü ──► komplikasyon türü + risk skoru
│
▼
iOS uygulaması (SwiftUI) ──► hekim sonuçları görür, bir hastaya dokunarak tüm bilgileri görüntüler


Ekran Görüntüsü

https://github.com/bircancigdem/OncoAI/blob/main/ekran%20go%CC%88ru%CC%88ntu%CC%88su%CC%88.pdf



Proje Yapısı

```
notebooks/01_veri_cogaltma.ipynb   CTGAN ile klinik veri çoğaltma, monoterapi + kombinasyon veri setlerinin birleştirilmesi
notebooks/02_fuzzy_logic.ipynb     Yaş / PD-L1 üyelik fonksiyonları ve bulanık mantık tedavi önerisi
notebooks/03_semifinal.ipynb       SMOTE + XGBoost + SHAP, eşik optimizasyonu, kalibrasyon, S-Learner + IPTW
notebooks/04_final.ipynb           Final model: hasta bazlı tedavi, başarı olasılığı ve komplikasyon tahmini
src/teknofest_pipeline.py          Yarı final için tek dosyalık XGBoost + SHAP + fuzzy pipeline
backend/service.py                 FastAPI servisi (iOS uygulamasının kullandığı API)
ios/                               SwiftUI hekim uygulaması (giriş, hasta paneli, açıklamalar)
data/synthetic/                    Sentetik örnek veri setleri
figures/                           SHAP ve karmaşıklık matrisi grafikleri
```

Veri Gizliliği

Gerçek klinik veriler ve hasta bazlı çıktılar KVKK gereği bu depoda paylaşılmamıştır; yalnızca sentetik örnek veri setleri yer almaktadır. Notebook çıktıları bu nedenle temizlenmiştir.

Çalıştırma

```bash
pip install -r requirements.txt
uvicorn backend.service:app --reload        # API: http://127.0.0.1:8000
```

iOS uygulaması için `ios/final_mobile.xcodeproj` dosyasını Xcode ile açın ve `Config.plist` içindeki `API_BASE_URL` değerini backend adresinize göre güncelleyin.
