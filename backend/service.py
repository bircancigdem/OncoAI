# service.py  —  per-treatment (separate) modeller + komplikasyonlar
import warnings
warnings.filterwarnings("ignore")

from typing import Optional, Union, Dict
import numpy as np, pandas as pd

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response

from sklearn.preprocessing import OneHotEncoder, StandardScaler, LabelEncoder
from sklearn.compose import ColumnTransformer
from sklearn.model_selection import train_test_split
from sklearn.calibration import CalibratedClassifierCV
from xgboost import XGBClassifier, XGBRegressor
from collections import OrderedDict

# -------------------- AYARLAR --------------------
CSV_PATH = "final_dataset_with_complication_types_risk_added_with_names.csv"
VAL_SIZE = 0.30
SEED = 42
np.random.seed(SEED)

# -------------------- VERİ -----------------------
df = pd.read_csv(CSV_PATH)

# Yaş metinse sayıya çevir
if df["age"].dtype == "O":
    age_map = {"Young": 30, "Middle-Aged": 60, "Senior": 75, "Elderly": 85}
    df["age"] = df["age"].map(age_map).fillna(df["age"]).astype(float)

# io_group türet
def to_group(io_type):
    if io_type is None or pd.isna(io_type):
        return "Monotherapy"
    key = str(io_type).strip().lower()
    mapping = {
        "pd-1 monotherapy": "Monotherapy",
        "pd-l1 monotherapy": "Monotherapy",
        "chemo + pd-1": "Chemo_IO",
        "chemo + pd-l1": "Chemo_IO",
        "ctla-4 + pd-1 combo": "Other",
        "io-contraindicated": "Other",
    }
    return mapping.get(key, "Other")

if "io_group" not in df.columns:
    df["io_group"] = df["io_type"].apply(to_group) if "io_type" in df.columns else "Monotherapy"

# Zorunlu kolonlar
need = [
    "pd_l1","tmb","age","msi","metastasis","ecog_score",
    "smoking_status","cancer_stage","treatment_start_days",
    "response","io_group"
]
miss = [c for c in need if c not in df.columns]
if miss:
    raise RuntimeError(f"Eksik kolon(lar): {miss}")

# Opsiyoneller
has_comp_type   = "complication_type" in df.columns
has_comp_risk   = "complication_risk_pct" in df.columns
has_full_name   = "full_name" in df.columns
has_cancer_type = "cancer_type" in df.columns

# Tür düzeltmeleri
df = df.dropna(subset=["response"]).copy()
df["response"]  = df["response"].astype(int)
df["io_group"]  = df["io_group"].astype(str)

if has_comp_type:
    df["complication_type"] = df["complication_type"].astype(str)
if has_comp_risk:
    df["complication_risk_pct"] = pd.to_numeric(df["complication_risk_pct"], errors="coerce")

# Hasta id
df = df.reset_index(drop=True).copy()
df["patient_id"] = np.arange(1, len(df) + 1).astype(int)

# -------------------- ÖZELLİKLER -----------------
features_num  = ["pd_l1","tmb","age","ecog_score","treatment_start_days"]
features_cat  = ["msi","metastasis","smoking_status","cancer_stage"]
base_features = features_num + features_cat
treat_col     = "io_group"

# --- 1) Komplikasyon/tek-model hattı ---
common_ct = ColumnTransformer([
    ("num", StandardScaler(), features_num),
    ("cat", OneHotEncoder(handle_unknown="ignore"), features_cat + [treat_col]),
])
X_all     = df[base_features + [treat_col]].copy()
y_success = df["response"].astype(int).values
X_proc    = common_ct.fit_transform(X_all).astype(np.float32)

# Başarı modeli
base_clf = XGBClassifier(
    objective="binary:logistic", eval_metric="logloss",
    n_estimators=500, max_depth=4, learning_rate=0.06,
    subsample=0.9, colsample_bytree=0.9, random_state=SEED, n_jobs=-1
)
X_tr, X_va, y_tr, y_va = train_test_split(
    X_proc, y_success, test_size=VAL_SIZE, random_state=SEED, stratify=df[treat_col]
)
base_clf.fit(X_tr, y_tr)

# Kalibrasyon
try:
    cal_success = CalibratedClassifierCV(estimator=base_clf, method="isotonic", cv="prefit")
except TypeError:
    cal_success = CalibratedClassifierCV(base_estimator=base_clf, method="isotonic", cv="prefit")
cal_success.fit(X_va, y_va)

pred_va  = cal_success.predict_proba(X_va)[:, 1]
avg_true = float(y_va.mean())
avg_pred = float(pred_va.mean()) if pred_va.mean() > 1e-9 else 1.0
CORR     = avg_true / avg_pred
def _adj(p: float) -> float:
    return float(np.clip(p * CORR, 0.0, 1.0))

# --- 2) Her tedaviye ayrı model hattı ---
ALL_TREATS = sorted(df[treat_col].astype(str).unique().tolist()+["Monotherapy","Chemo_IO","Other"])
base_ct = ColumnTransformer([
    ("num", StandardScaler(), features_num),
    ("cat", OneHotEncoder(handle_unknown="ignore"), features_cat),
])
X_base = df[base_features].copy()
X_base_proc = base_ct.fit_transform(X_base).astype(np.float32)
y_success = df["response"].astype(int).values

MIN_SAMPLES_PER_TREAT = 20
treat_models: "OrderedDict[str, XGBClassifier]" = OrderedDict()
for t in ALL_TREATS:
    mask = (df[treat_col].astype(str) == t)
    n = int(mask.sum())
    if n < MIN_SAMPLES_PER_TREAT:
        continue
    X_t = X_base_proc[mask]
    y_t = y_success[mask]
    clf = XGBClassifier(
        objective="binary:logistic", eval_metric="logloss",
        n_estimators=400, max_depth=4, learning_rate=0.06,
        subsample=0.9, colsample_bytree=0.9, random_state=SEED, n_jobs=-1
    )
    clf.fit(X_t, y_t)
    treat_models[t] = clf

# -------------------- KOMPLİKASYON MODELLERİ ----------------
comp_type_clf: Optional[XGBClassifier] = None
comp_risk_reg: Optional[XGBRegressor]  = None
label_enc: Optional[LabelEncoder]      = None

if has_comp_type:
    y_comp_type = df["complication_type"].astype(str).values
    label_enc   = LabelEncoder().fit(y_comp_type)
    y_comp_enc  = label_enc.transform(y_comp_type)
    comp_type_clf = XGBClassifier(
        objective="multi:softprob", num_class=len(label_enc.classes_),
        eval_metric="mlogloss", n_estimators=400, max_depth=4, learning_rate=0.06,
        subsample=0.9, colsample_bytree=0.9, random_state=SEED, n_jobs=-1
    )
    comp_type_clf.fit(X_proc, y_comp_enc)

if has_comp_risk:
    y_risk = pd.to_numeric(df["complication_risk_pct"], errors="coerce").fillna(0.0)
    if y_risk.max() > 1.5:
        y_risk = (y_risk / 100.0).clip(0, 1)
    comp_risk_reg = XGBRegressor(
        n_estimators=400, max_depth=4, learning_rate=0.06,
        subsample=0.9, colsample_bytree=0.9, random_state=SEED, n_jobs=-1
    )
    comp_risk_reg.fit(X_proc, y_risk)

# -------------------- FASTAPI ---------------------
app = FastAPI(title="OncoAI API", version="2.0")

@app.middleware("http")
async def add_charset_header(request, call_next):
    resp: Response = await call_next(request)
    ct = resp.headers.get("content-type", "")
    if resp.media_type == "application/json" and "charset" not in ct:
        resp.headers["content-type"] = "application/json; charset=utf-8"
    return resp

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"ok": True}

@app.get("/search")
def search(name: str = Query(..., description="Hasta adı (parça eşleşme)")):
    q = name.strip().lower()
    if not q:
        return []
    if "full_name" not in df.columns:
        raise HTTPException(500, "Veride 'full_name' kolonu yok.")
    m = df["full_name"].astype(str).str.lower().str.contains(q, na=False)
    res = df.loc[m, ["patient_id","full_name","age","cancer_stage","ecog_score"]].copy()
    res = res.rename(columns={
        "patient_id":"id","full_name":"fullName","cancer_stage":"stage","ecog_score":"ecogScore"
    })
    res["id"]        = res["id"].astype(int)
    res["age"]       = pd.to_numeric(res["age"], errors="coerce").fillna(0).astype(int)
    res["ecogScore"] = pd.to_numeric(res["ecogScore"], errors="coerce").fillna(0).astype(int)
    res["stage"]     = res["stage"].astype(str)
    res["fullName"]  = res["fullName"].astype(str)
    if has_cancer_type:
        res["cancerType"] = df.loc[m, "cancer_type"].astype(str)
    else:
        res["cancerType"] = ""
    return res.to_dict(orient="records")

def _row_by_pid(pid_int: int) -> pd.Series:
    hit = df.loc[df["patient_id"] == pid_int]
    if hit.empty:
        raise KeyError(f"patient_id={pid_int} bulunamadı")
    return hit.iloc[0]

def _success_prob_for(row: pd.Series, treat_name: str) -> float:
    if treat_name in treat_models:
        base = pd.DataFrame([{k: row[k] for k in base_features}])
        Xp_base = base_ct.transform(base).astype(np.float32)
        p = float(treat_models[treat_name].predict_proba(Xp_base)[0, 1])
        return float(np.clip(p, 0.0, 1.0))
    else:
        base = pd.DataFrame([{k: row[k] for k in base_features}])
        base[treat_col] = treat_name
        Xp = common_ct.transform(base).astype(np.float32)
        p = float(cal_success.predict_proba(Xp)[0, 1])
        return _adj(p)

def _complications_for(row: pd.Series, treat_name: str):
    comp_type = None
    comp_risk_pct = None
    base = pd.DataFrame([{k: row[k] for k in base_features}])
    base[treat_col] = treat_name
    Xp = common_ct.transform(base).astype(np.float32)
    if comp_type_clf is not None and label_enc is not None:
        probs = comp_type_clf.predict_proba(Xp)[0]
        comp_type = str(label_enc.classes_[int(np.argmax(probs))])
    if comp_risk_reg is not None:
        r = float(comp_risk_reg.predict(Xp)[0])
        comp_risk_pct = float(np.clip(r, 0.0, 1.0) * 100.0)
    return comp_type, (None if comp_risk_pct is None else round(comp_risk_pct, 2))

def _predict_for(row: pd.Series, treat_name: str):
    p_succ = _success_prob_for(row, treat_name)
    ctype, crisk = _complications_for(row, treat_name)
    return {
        "treatment": treat_name,
        "success_probability": round(p_succ, 4),
        "complication_type": ctype,
        "complication_risk_pct": crisk,
    }

@app.get("/predict")
def predict(patient_id: Union[int, str] = Query(..., description="patient_id (int veya string)")):
    try:
        pid = int(str(patient_id).strip())
    except Exception:
        raise HTTPException(422, "patient_id int olmalı")

    try:
        row = _row_by_pid(pid)
    except KeyError as e:
        raise HTTPException(404, str(e))

    all_treats_payload = [_predict_for(row, t) for t in ALL_TREATS]
    best = max(all_treats_payload, key=lambda d: d["success_probability"])

    # --- Alternatifleri düzenle (tekil + önerilen hariç + skorla sıralı)
    seen = set()
    alts_unique_sorted = []
    for d in all_treats_payload:
        key = d["treatment"].strip().lower()
        if key in seen:
            continue
        seen.add(key)
        if key == best["treatment"].strip().lower():
            continue
        alts_unique_sorted.append({
            "treatment": d["treatment"],
            "success_probability": d["success_probability"]
        })
    alts_unique_sorted.sort(key=lambda x: x["success_probability"], reverse=True)

    seen_comp = set()
    comp_by_treat_unique = []
    for d in all_treats_payload:
        key = d["treatment"].strip().lower()
        if key in seen_comp:
            continue
        seen_comp.add(key)
        comp_by_treat_unique.append({
            "treatment": d["treatment"],
            "complication_type": d.get("complication_type"),
            "complication_risk_pct": d.get("complication_risk_pct"),
        })

    now = pd.Timestamp.utcnow()
    history = []
    for i in range(10):
        history.append({
            "timestamp": (now - pd.Timedelta(minutes=5*(9-i))).isoformat(),
            "success_probability": round(
                float(np.clip(best["success_probability"] - 0.03 + 0.006*i, 0.0, 1.0)), 4
            ),
        })

    clinical = {
        "pd_l1":          float(row["pd_l1"]) if pd.notna(row["pd_l1"]) else None,
        "tmb":            float(row["tmb"]) if pd.notna(row["tmb"]) else None,
        "age":            int(row["age"]) if pd.notna(row["age"]) else None,
        "metastasis":     str(row["metastasis"]) if pd.notna(row["metastasis"]) else None,
        "ecog_score":     int(row["ecog_score"]) if pd.notna(row["ecog_score"]) else None,
        "smoking_status": str(row["smoking_status"]) if pd.notna(row["smoking_status"]) else None,
        "cancer_stage":   str(row["cancer_stage"]) if pd.notna(row["cancer_stage"]) else None,
    }

    return {
        "patient_id": pid,
        "full_name": (row["full_name"] if has_full_name else None),
        "recommended_treatment": best["treatment"],
        "current_probability":   best["success_probability"],
        "alternatives": alts_unique_sorted,
        "complication_type":     best["complication_type"],
        "complication_risk_pct": best["complication_risk_pct"],
        "complications_by_treatment": comp_by_treat_unique,
        "clinical": clinical,
        "history": history,
    }