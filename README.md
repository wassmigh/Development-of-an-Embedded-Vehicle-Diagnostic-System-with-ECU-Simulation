# 🚗 DiagSmarter: Smart Embedded Vehicle Diagnostic System

DiagSmarter is a low-cost, end-to-end embedded vehicle diagnostic platform based on the CAN bus protocol and STM32 microcontrollers. It features an OBD-II diagnostic sniffer, a realistic hardware ECU simulator, and a cloud-connected Raspberry Pi gateway that streams real-time vehicle telemetry to a Firebase backend for remote monitoring via a mobile application.

This project was developed as an End-of-Year Project (PFA) at ISIMG (Higher Institute of Computer Sciences and Multimedia of Gabes).

---

## 📑 Table of Contents
- [Architecture](#-architecture)
- [Key Features](#-key-features)
- [Hardware Requirements](#-hardware-requirements)
- [Software & Technologies](#-software--technologies)
- [Repository Structure](#-repository-structure)
- [Setup and Installation](#-setup-and-installation)
- [Future Improvements](#-future-improvements)
- [Authors](#-authors)

---

## 🏗️ Architecture

The system is divided into four main interconnected components:

1. **CAN Sniffer Node (STM32 + MCP2515)**  
   Acts as the main diagnostic tool. It polls the CAN bus sending OBD-II requests (Mode 01 for live data, Mode 03 for DTCs) and decodes the responses. The decoded data (RPM, Speed, Temperature, Fuel Level, Battery Voltage, DTCs) is packaged into JSON and sent over UART.

2. **ECU Simulator Node (STM32 + MCP2515)**  
   A reactive node that simulates a real vehicle's Electronic Control Unit (ECU). It listens for OBD-II broadcast requests and responds with dynamically changing, realistic engine sensor values. This eliminates the need for a real vehicle during testing.

3. **AI/Cloud Gateway (Raspberry Pi 5)**  
   A Python-based server that reads the JSON UART stream from the Sniffer, performs data aggregation/classification, and pushes the telemetry to a Firebase Realtime Database. 

4. **Mobile Application (Flutter)**  
   A dynamic dashboard application that listens to Firebase state changes in real-time to display gauges, battery status, and active Diagnostic Trouble Codes (DTC).

---

## ✨ Key Features
- **Complete Diagnostic Chain:** From physical CAN bus signaling to a mobile UI.
- **Hardware ECU Simulation:** Dynamic RPM cycling and temperature warm-up mimicking real engine behaviors.
- **DTC Decoding:** Automatically requests, receives, and decodes vehicle fault codes (e.g., `P0300`, `U0123`).
- **Cloud Analytics:** Computes daily averages, peak RPMs, and provides battery health classification.
- **Cost-Effective:** Built entirely using low-cost off-the-shelf components.

---

## 📱 Mobile App Interfaces

Here are some previews of the DiagSmarter mobile application dashboard:

<div align="center">
  <img src="dashboard1.jpeg" width="22%" alt="Dashboard" />
  <img src="livedata1.jpeg" width="22%" alt="Live Data" />
  <img src="health1.jpeg" width="22%" alt="Vehicle Health" />
  <img src="history1.jpeg" width="22%" alt="History" />
</div>

---

## 🛠️ Hardware Requirements
- **2x** STM32F407G-DISC1 Development Boards
- **2x** MCP2515 CAN Controller Modules (connected via SPI)
- **2x** TJA1050 CAN Transceivers
- **1x** Raspberry Pi 5
- Jumper wires & USB to TTL converter (optional, for debugging)

---

## 💻 Software & Technologies
- **Firmware:** C (C99) with STM32Cube HAL
- **Gateway Script:** Python 3.11 (`pyserial`, `firebase-admin`)
- **Cloud/Database:** Firebase Realtime Database
- **Mobile Frontend:** Flutter / Dart
- **IDE:** STM32CubeIDE 1.15

---

## 📂 Repository Structure

```text
OBD2/
├── can_sniffer/             # STM32 Firmware for the OBD-II Sniffer node
├── car_simulator/           # STM32 Firmware for the realistic ECU Simulator
├── rpi_obd_firebase_server.py # Raspberry Pi Python Gateway to Firebase
├── serviceAccountKey.json   # (Ignored) Firebase Admin SDK private key
├── rapport_DiagSmarter.tex  # LaTeX source code for the academic report
└── Architecture du DiagSmarter/ # Architecture diagrams and wiring schematics
```

---

## 🚀 Setup and Installation

### 1. STM32 Nodes Setup
1. Open the `can_sniffer` and `car_simulator` projects in **STM32CubeIDE**.
2. Flash the `car_simulator` firmware to the first STM32 board.
3. Flash the `can_sniffer` firmware to the second STM32 board.
4. Connect the CAN High and CAN Low pins of both MCP2515 modules together. Ensure the MCP2515 modules are powered with 3.3V to match STM32 logic levels.

### 2. Raspberry Pi Gateway Setup
1. Connect the Sniffer STM32 UART TX (PA2) to the Raspberry Pi RX (GPIO 15), and connect common ground (GND).
2. Install Python dependencies:
   ```bash
   pip install pyserial firebase-admin
   ```
3. Place your Firebase `serviceAccountKey.json` in the root directory.
4. Run the server:
   ```bash
   python3 rpi_obd_firebase_server.py
   ```

---

## 🔮 Future Improvements
- **Real-Time OS (FreeRTOS):** Transitioning the STM32 firmware to FreeRTOS to manage tasks and interrupts more efficiently.
- **Machine Learning Integration:** Deploy an ML model on the Raspberry Pi to analyze engine temperature, DTCs, and RPM to predict anomalies and provide a global health score.
- **User Authentication:** Add multi-user support in the mobile application to allow different users to track their specific vehicles.
- **Dynamic Battery Simulation:** Enhance the ECU simulator to dynamically vary battery voltage drops and charging spikes.

---

## 👨‍💻 Authors
Developed by:
* **Gheriani Wassmi**
* **Charef Ahmed**

Supervised by **Mrs. Mounira Tarhouni**, ISIMG.

*Academic Year: 2025/2026*
