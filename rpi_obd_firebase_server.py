#!/usr/bin/env python3
"""
=============================================================================
 obd_firebase_server.py  —  Raspberry Pi UART → Firebase Realtime Database
=============================================================================

 Noeuds Firebase mis à jour à chaque cycle :
   liveData/
   health/activeDTCs/
   history/summary/day/{YYYY-MM-DD}/        ← moyennes cumulées du jour
   history/performanceTimeline/{YYYY-MM-DD}/ ← loadPercent + efficiency du jour

 Câblage :
   STM32 PA2 (TX USART2)  →  RPi GPIO15 / pin 10 (RXD)
   STM32 GND              →  RPi GND  (masse commune obligatoire)

 Dépendances :
   pip install pyserial firebase-admin
=============================================================================
"""

import json
import time
import logging
from datetime import datetime

import serial
import firebase_admin
from firebase_admin import credentials, db

# ─── CONFIGURATION ────────────────────────────────────────────────────────────

SERVICE_ACCOUNT_KEY = "C:/Users/wassm/Desktop/OBD2/serviceAccountKey.json"
FIREBASE_DB_URL     = "https://smartcardiag-default-rtdb.europe-west1.firebasedatabase.app/"

USER_ID    = "user_12345"
VEHICLE_ID = "vehicle_001"

SERIAL_PORT    = "COM5"
BAUD_RATE      = 115200
SERIAL_TIMEOUT = 5

# ─── LOGGING ──────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger(__name__)

# ─── ACCUMULATEUR JOURNALIER (RAM) ────────────────────────────────────────────
#
# Accumule les lectures du jour courant pour calculer avg / max / peak
# sans relire Firebase à chaque cycle.
#
# Réinitialisé automatiquement à minuit (changement de date détecté).

_acc: dict = {
    "date":     "",   # "YYYY-MM-DD" du jour en cours
    "rpm_sum":  0,
    "rpm_peak": 0,
    "temp_sum": 0,
    "temp_max": 0,
    "load_sum": 0,
    "count":    0,
}


def _today() -> str:
    """Date du jour au format YYYY-MM-DD (utilisée comme clé Firebase)."""
    return datetime.now().strftime("%Y-%m-%d")


def _reset_acc(date_str: str) -> None:
    global _acc
    _acc = {"date": date_str, "rpm_sum": 0, "rpm_peak": 0,
            "temp_sum": 0, "temp_max": 0, "load_sum": 0, "count": 0}
    log.info("Nouveau jour (%s) — accumulateur réinitialisé", date_str)


def _accumulate(rpm: int, temp: int, load: int) -> None:
    today = _today()
    if _acc["date"] != today:
        _reset_acc(today)
    _acc["rpm_sum"]  += rpm
    _acc["rpm_peak"]  = max(_acc["rpm_peak"], rpm)
    _acc["temp_sum"] += temp
    _acc["temp_max"]  = max(_acc["temp_max"], temp)
    _acc["load_sum"] += load
    _acc["count"]    += 1


def _averages() -> dict:
    """Retourne les moyennes/peak calculées depuis l'accumulateur."""
    n = _acc["count"]
    if n == 0:
        return {}
    return {
        "rpm_avg":  round(_acc["rpm_sum"]  / n),
        "rpm_peak": _acc["rpm_peak"],
        "temp_avg": round(_acc["temp_sum"] / n),
        "temp_max": _acc["temp_max"],
        "load_avg": round(_acc["load_sum"] / n),
    }

# ─── CLASSIFICATION ───────────────────────────────────────────────────────────

def classify_battery(v: float) -> str:
    if v >= 13.8: return "OPTIMAL"
    if v >= 12.4: return "NORMAL"
    if v >= 11.8: return "LOW"
    return "CRITICAL"


def classify_load(avg: int) -> str:
    """Rating textuel de la charge moteur moyenne."""
    if avg <= 30: return "OPTIMAL"
    if avg <= 60: return "MODERATE"
    if avg <= 80: return "HIGH"
    return "CRITICAL"


def efficiency_score(load_avg: int) -> int:
    """Score d'efficacité 0-100 (inversement proportionnel à la charge)."""
    return max(0, min(100, 100 - load_avg))

# ─── DTC helpers ──────────────────────────────────────────────────────────────

DTC_DESCRIPTIONS = {
    "P0300": "Random/Multiple Cylinder Misfire Detected",
    "P0301": "Cylinder 1 Misfire Detected",
    "P0302": "Cylinder 2 Misfire Detected",
    "P0303": "Cylinder 3 Misfire Detected",
    "P0171": "System Too Lean (Bank 1)",
    "P0172": "System Too Rich (Bank 1)",
    "P0420": "Catalyst System Efficiency Below Threshold (Bank 1)",
    "P0505": "Idle Control System Malfunction",
}

def dtc_description(code: str) -> str:
    return DTC_DESCRIPTIONS.get(code, f"Fault code {code} — refer to service manual")

def dtc_severity(code: str) -> str:
    if code.startswith("P0"):
        return "ORANGE" if len(code) > 2 and code[2] == "3" else "YELLOW"
    if code.startswith(("P1", "P2")):
        return "ORANGE"
    return "YELLOW"

# ─── MISE À JOUR FIREBASE ─────────────────────────────────────────────────────

def push_to_firebase(parsed: dict) -> None:
    """
    Écrit dans Firebase les 4 noeuds suivants :

      [1] liveData/
      [2] health/activeDTCs/
      [3] history/summary/day/{YYYY-MM-DD}/
            coolantTemp/  avg  max
            engineLoad/   avg  rating
            engineSpeed/  avg  peak
      [4] history/performanceTimeline/{YYYY-MM-DD}/
            loadPercent   (= liveData/engineLoad, valeur instantanée)
            efficiency    (calculée depuis load_avg du jour)
    """
    now_ms  = int(time.time() * 1000)
    today   = _today()                          # ex: "2026-06-05"
    base    = f"users/{USER_ID}/vehicles/{VEHICLE_ID}"

    # Lecture des valeurs brutes
    rpm     = int(parsed.get("rpm",             0))
    speed   = int(parsed.get("speed",           0))
    temp    = int(parsed.get("temp",            0))
    fuel    = int(parsed.get("fuel",            0))
    load    = int(parsed.get("engine_load",     0))
    conso   = float(parsed.get("avg_consumption", 0.0))
    battery = float(parsed.get("battery",       0.0))

    # ── [1] liveData ──────────────────────────────────────────────────────────
    live_data = {
        "timestamp":      now_ms,
        "rpm":            rpm,
        "speed":          speed,
        "temp":           temp,
        "fuelLevel":      fuel,
        "engineLoad":     load,
        "avgConsumption": conso,
        "isStreaming":    True,
        "battery": {
            "voltage": battery,
            "status":  classify_battery(battery)
        }
    }
    db.reference(f"{base}/liveData").update(live_data)
    log.info("[liveData] RPM=%d  Speed=%d km/h  Temp=%d°C  Fuel=%d%%  "
             "Load=%d%%  Conso=%.1f L/100  Bat=%.2fV",
             rpm, speed, temp, fuel, load, conso, battery)

    # ── Mise à jour accumulateur + calcul des moyennes ────────────────────────
    _accumulate(rpm, temp, load)
    avgs = _averages()

    # ── [3] history/summary/day/{DATE}/ ───────────────────────────────────────
    #
    #  Les valeurs avg/max/peak sont calculées sur TOUTES les lectures
    #  reçues depuis le début du jour courant (accumulateur RAM).
    #
    #  Mapping :
    #    coolantTemp.avg  ←  moyenne de liveData/temp
    #    coolantTemp.max  ←  max     de liveData/temp
    #    engineLoad.avg   ←  moyenne de liveData/engineLoad
    #    engineLoad.rating←  classifié depuis engineLoad.avg
    #    engineSpeed.avg  ←  moyenne de liveData/rpm
    #    engineSpeed.peak ←  max     de liveData/rpm
    #
    day_summary = {
        "coolantTemp": {
            "avg": avgs["temp_avg"],
            "max": avgs["temp_max"],
        },
        "engineLoad": {
            "avg":    avgs["load_avg"],
            "rating": classify_load(avgs["load_avg"]),
        },
        "engineSpeed": {
            "avg":  avgs["rpm_avg"],
            "peak": avgs["rpm_peak"],
        },
    }
    db.reference(f"{base}/history/summary/day/{today}").update(day_summary)
    log.info("[history/summary/day/%s] coolantTemp avg=%d°C max=%d | "
             "engineLoad avg=%d%% (%s) | engineSpeed avg=%d peak=%d",
             today,
             avgs["temp_avg"], avgs["temp_max"],
             avgs["load_avg"], day_summary["engineLoad"]["rating"],
             avgs["rpm_avg"],  avgs["rpm_peak"])

    # ── [4] history/performanceTimeline/{DATE}/ ───────────────────────────────
    #
    #  loadPercent = valeur instantanée de liveData/engineLoad
    #               (même valeur, écrite simultanément dans les deux noeuds)
    #  efficiency  = score calculé depuis la moyenne journalière du load
    #
    perf_entry = {
        "loadPercent": load,                        # identique à liveData/engineLoad
        "efficiency":  efficiency_score(avgs["load_avg"]),
    }
    db.reference(f"{base}/history/performanceTimeline/{today}").update(perf_entry)
    log.info("[history/performanceTimeline/%s] loadPercent=%d  efficiency=%d",
             today, perf_entry["loadPercent"], perf_entry["efficiency"])

    # ── [2] health/activeDTCs ─────────────────────────────────────────────────
    dtcs: list = parsed.get("dtcs", [])
    if dtcs:
        dtc_updates = {
            code: {
                "description": dtc_description(code),
                "severity":    dtc_severity(code),
                "timestamp":   now_ms,
            }
            for code in dtcs if code
        }
        if dtc_updates:
            db.reference(f"{base}/health/activeDTCs").update(dtc_updates)
            log.info("[activeDTCs] %s", list(dtc_updates.keys()))
    else:
        log.info("[activeDTCs] Aucun DTC actif — inchangé")

# ─── PARSING JSON ─────────────────────────────────────────────────────────────

def parse_line(line: str) -> dict | None:
    """
    Parse une ligne JSON compacte terminée par \\n.
    Les lignes de debug texte STM32 (ne commençant pas par '{') sont ignorées.

    Format attendu :
      {"rpm":3200,"speed":68,"temp":92,"fuel":64,
       "engine_load":24,"avg_consumption":7.4,
       "battery":14.20,"dtcs":["P0300"]}
    """
    line = line.strip()
    if not line.startswith("{"):
        return None
    try:
        data = json.loads(line)
        required = {"rpm", "speed", "temp", "fuel", "battery",
                    "engine_load", "avg_consumption", "dtcs"}
        missing = required - data.keys()
        if missing:
            log.warning("JSON incomplet — champs manquants : %s", missing)
            return None
        return data
    except json.JSONDecodeError as exc:
        log.warning("Erreur JSON : %s  |  ligne : %s", exc, line[:80])
        return None

# ─── BOUCLE PRINCIPALE ────────────────────────────────────────────────────────

def main() -> None:
    log.info("═══════════════════════════════════════════")
    log.info("  OBD-II Firebase Server — Raspberry Pi")
    log.info("═══════════════════════════════════════════")

    # Init Firebase
    log.info("Connexion Firebase → %s", FIREBASE_DB_URL)
    cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
    firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DB_URL})
    log.info("Firebase initialisé ✓")

    db.reference(
        f"users/{USER_ID}/vehicles/{VEHICLE_ID}/liveData/isStreaming"
    ).set(True)

    # Ouverture port série
    log.info("Ouverture %s @ %d baud", SERIAL_PORT, BAUD_RATE)
    ser = serial.Serial(
        port=SERIAL_PORT,
        baudrate=BAUD_RATE,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=SERIAL_TIMEOUT
    )
    log.info("Port série ouvert ✓  — en attente de données STM32...")

    consecutive_errors = 0
    MAX_ERRORS = 10

    try:
        while True:
            raw = ser.readline()
            if not raw:
                log.debug("Timeout série — aucune donnée reçue")
                continue

            line = raw.decode("utf-8", errors="replace")
            log.debug("UART brut : %s", line.strip())

            parsed = parse_line(line)
            if parsed is None:
                log.debug("Ligne non-JSON ignorée")
                continue

            try:
                push_to_firebase(parsed)
                consecutive_errors = 0
            except Exception as exc:
                consecutive_errors += 1
                log.error("Erreur Firebase (%d/%d) : %s",
                          consecutive_errors, MAX_ERRORS, exc)
                if consecutive_errors >= MAX_ERRORS:
                    log.critical("Trop d'erreurs Firebase consécutives — arrêt")
                    break

    except KeyboardInterrupt:
        log.info("Arrêt demandé (Ctrl+C)")

    finally:
        try:
            db.reference(
                f"users/{USER_ID}/vehicles/{VEHICLE_ID}/liveData/isStreaming"
            ).set(False)
            log.info("isStreaming → false")
        except Exception:
            pass
        if ser.is_open:
            ser.close()
            log.info("Port série fermé")
        log.info("Serveur arrêté.")


if __name__ == "__main__":
    main()