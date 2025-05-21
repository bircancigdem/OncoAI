# 📦 GEREKLİ KÜtÜPHANELER
import pandas as pd
import numpy as np
import shap
import matplotlib.pyplot as plt
import skfuzzy as fuzz
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.metrics import (classification_report, accuracy_score, roc_auc_score,
                             precision_recall_curve, ConfusionMatrixDisplay)
from imblearn.over_sampling import SMOTE
from xgboost import XGBClassifier
from scipy.sparse import issparse

# 📄 VERİ YÜKLEME
file_path = "synthetic_imbalanced_300_clinical_dataset_enriched.csv"
df = pd.read_csv(file_path)
df = df.dropna()

# 🎯 ÖZELLİKLER
target = "response"
features = ['pd_l1', 'tmb', 'age', 'msi', 'metastasis',
            'ecog_score', 'smoking_status', 'cancer_stage', 'treatment_start_days']

X = df[features]
y = df[target]

# 🔧 ÖN İŞLEME
numeric_features = ['tmb', 'pd_l1', 'ecog_score', 'treatment_start_days']
categorical_features = ['age', 'msi', 'smoking_status', 'cancer_stage']
binary_features = ['metastasis']

numeric_pipeline = Pipeline([("scaler", StandardScaler())])
categorical_pipeline = Pipeline([("onehot", OneHotEncoder(handle_unknown="ignore"))])
preprocessor = ColumnTransformer([
    ("num", numeric_pipeline, numeric_features),
    ("cat", categorical_pipeline, categorical_features)
], remainder='passthrough')

X_processed = preprocessor.fit_transform(X)
feature_names = preprocessor.get_feature_names_out()

# ⚖️ SMOTE
smote = SMOTE(random_state=42, k_neighbors=1)
X_resampled, y_resampled = smote.fit_resample(X_processed, y)

# 🔀 TRAIN/TEST SPLIT
X_train, X_test, y_train, y_test = train_test_split(
    X_resampled, y_resampled, test_size=0.2, stratify=y_resampled, random_state=42)

# 🌲 MODEL
model = XGBClassifier(use_label_encoder=False, eval_metric='logloss', random_state=42)
model.fit(X_train, y_train)
y_proba = model.predict_proba(X_test)[:, 1]

# 🌟 THRESHOLD OPTİMİZASYONU
prec, recall, thresholds = precision_recall_curve(y_test, y_proba)
f1_scores = 2 * (prec * recall) / (prec + recall + 1e-6)
best_thresh = thresholds[np.argmax(f1_scores)]
y_pred_opt = (y_proba >= best_thresh).astype(int)

print(f"\n🔍 Optimum Eşik Değeri: {best_thresh:.2f}")
print("\n📊 Classification Report (Optimum Eşik):\n")
print(classification_report(y_test, y_pred_opt))
print("✅ Accuracy:", round(accuracy_score(y_test, y_pred_opt), 4))
print("📈 ROC AUC Score:", round(roc_auc_score(y_test, y_proba), 4))

# 🔳 CONFUSION MATRIX
ConfusionMatrixDisplay.from_predictions(y_test, y_pred_opt,
                                        display_labels=["Başarısız", "Başarılı"],
                                        cmap="Blues")
plt.title(f"Optimum Eşik ile Confusion Matrix\n(Eşik = {best_thresh:.2f})")
plt.show()

# 🧠 SHAP ANALİZİ
explainer = shap.Explainer(model, X_train)
X_test_df = pd.DataFrame(X_test[:50].toarray() if issparse(X_test[:50]) else X_test[:50],
                         columns=feature_names)
shap_values = explainer(X_test_df, check_additivity=False)
shap.plots.bar(shap_values)
shap.plots.waterfall(shap_values[0])

# 🧐 BULANIK MANTIK
x_pdl1 = np.arange(0, 101, 1)
x_tmb = np.arange(0, 51, 1)
x_age = np.arange(20, 101, 1)
x_ecog = np.arange(0, 5, 1)
x_delay = np.arange(0, 101, 1)

pdl1_high = fuzz.trapmf(x_pdl1, [30, 50, 100, 100])
tmb_high = fuzz.trapmf(x_tmb, [5, 10, 50, 50])
age_old = fuzz.trapmf(x_age, [60, 70, 100, 100])
ecog_bad = fuzz.trapmf(x_ecog, [2, 3, 4, 4])
delay_late = fuzz.trapmf(x_delay, [30, 60, 100, 100])

# 🌟 ÖRNEK HASTA
idx = 2
row = df.iloc[idx]

pdl1 = row['pd_l1']
tmb = row['tmb']
age = 80 if row['age'] == "Elderly" else 60
msi = row['msi']
metastasis = row['metastasis']
ecog = row['ecog_score']
delay = row['treatment_start_days']
smoking = row['smoking_status'].lower()
stage = row['cancer_stage']

pdl1_h = fuzz.interp_membership(x_pdl1, pdl1_high, pdl1)
tmb_h = fuzz.interp_membership(x_tmb, tmb_high, tmb)
age_o = fuzz.interp_membership(x_age, age_old, age)
ecog_b = fuzz.interp_membership(x_ecog, ecog_bad, ecog)
delay_l = fuzz.interp_membership(x_delay, delay_late, delay)

# 🔄 BULANIK KARAR KURALLARI
if "msi-h" in msi.lower():
    suggestion = "🟢 Monoterapi (MSI-H hasta)"
elif tmb_h > 0.6 and pdl1_h < 0.4:
    suggestion = "🟡 Kombinasyon (TMB yüksek, PD-L1 düşük)"
elif pdl1_h > 0.6 and tmb_h > 0.6:
    suggestion = "🟢 Monoterapi (PD-L1 ve TMB yüksek)"
elif pdl1_h < 0.3 and tmb_h < 0.3:
    suggestion = "🔴 Yetersiz veri – başka biyobelirteçler gerekli"
elif age_o > 0.6 or metastasis == 1 or ecog_b > 0.5 or delay_l > 0.5:
    if smoking in ['current smoker', 'former smoker'] or stage in ['III', 'IV']:
        suggestion = "🟡 Kombinasyon (yüksek risk grubu – ileri evre/sigara geçmişi)"
    else:
        suggestion = "🟡 Kombinasyon düşünülebilir, yan etki riski varsa monoterapi"
else:
    suggestion = "🔴 Klinik değerlendirme ile karar verilmeli"

# 🔬 MODEL TAHMİNİ (TEK HASTA)
sample_X = X_processed[idx]
proba = model.predict_proba([sample_X])[0][1]

print("\n🤠 Model Tahmini:")
print(f"Bu hasta için tedavi başarılı olma olasılığı: %{proba * 100:.2f}")
print("\n📌 Bulanık Mantık Temelli Tedavi Önerisi:")
print(f"PD-L1: {pdl1}, TMB: {tmb}, ECOG: {ecog}, Gecikme: {delay}, Yaş (grup): {row['age']}, Sigara: {row['smoking_status']}, Evre: {stage}")
print("Öneri:", suggestion)
