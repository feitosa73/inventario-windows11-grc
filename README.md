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
