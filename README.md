# Windows 11 Local Inventory - GRC Focus

## Objective

This project provides a **deep local inventory for Windows 11 endpoints** with a focus on **GRC (Governance, Risk and Compliance)**.

It **does not replace** enterprise tools such as Intune, SCCM or EDR.
It **complements** them by enabling:

- Deep inspection on critical machines
- Evidence collection
- Detection of persistence, resource consumption and blind spots
- Executive decision support (KEEP / REVIEW / REMOVE)

---

## What this project does

The inventory collects and organizes:

- Installed Win32 applications
- Microsoft Store (UWP) applications
- Third-party services
- Auto-start services
- Third-party scheduled tasks
- Startup registry entries
- Consolidated JSON output for automation and AI analysis

---

## Project structure

```text
inventario-windows11-grc/
├── src/
│   ├── Inventario-Windows11-GRC.ps1   # Data collection
│   └── Report-Inventario-W11.ps1      # Executive analysis and prioritization
├── README.md
└── .gitignore

---

## How it works (high level)

1. **Data collection**
   - `Inventario-Windows11-GRC.ps1` runs locally on a Windows 11 endpoint
   - Collects applications, services, tasks and startup artifacts
   - Generates structured CSV files and a consolidated JSON

2. **Executive analysis**
   - `Report-Inventario-W11.ps1` consumes the generated inventory folder
   - Applies heuristics to identify persistence, consumption and governance gaps
   - Produces executive-ready outputs:
     - Executive summary (Markdown)
     - Prioritized CSVs for decision making

3. **Human decision layer**
   - The tool does **not** remove or disable anything automatically
   - Final decisions are always human-driven (KEEP / REVIEW / REMOVE)

