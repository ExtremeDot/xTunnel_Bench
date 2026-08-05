# Changelog & Release Notes

## [v1.3.1] - 2026-08-05

### ⚡ Fixed & Improved
* **Engine / Speedtest**: Replaced fragile `grep`-based JSON parsing with a dedicated `python3` parser for `iperf3` metrics extraction.
* **Error Handling**: Fixed `[ERROR] Failed to parse iperf3 test results` issue caused by multi-stream JSON array structures.
* **Fallback Logic**: Added automated fallback mechanisms for calculating throughput from both `sum_received` and `sum_sent` data nodes.

---

## [v1.3.0] - 2026-08-04

### 🚀 Added
* **Speedtest Module**: Integrated real-time TCP multi-stream bandwidth test via `iperf3`.
* **Traffic Usage Estimator**: Added dynamic data consumption notice based on test duration and throughput.
* **Interactive Duration Selector**: Added pre-configured presets (5s, 10s, custom duration) to prevent unexpected bandwidth burn.

### 🛡️ System & Firewall
* **Auto Firewall Management**: Automated UFW port dynamic mapping for `iperf3` diagnostic ports (`55210+`).
* **Dependency Check**: Added automatic verification and silent package installation for `python3` and `iperf3`.

---

## [v1.2.0] - 2026-08-01

### 🚀 Features
* **Multi-Tunnel Engine**: Full lifecycle management for up to 10 parallel FRP TCP tunnels.
* **Auto Location Detection**: Dynamic IRAN / KHAREJ detection via multi-fallback GEO IP APIs.
* **CRON Scheduler**: Built-in auto-restart scheduling via CronJobs.
* **Health Check**: Port probing engine (`nc`) for diagnosing remote server connection drops.
