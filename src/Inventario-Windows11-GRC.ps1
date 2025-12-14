<#
.SYNOPSIS
  Inventário Windows 11 orientado a GRC (sem SCCM/Intune).
.DESCRIPTION
  Coleta evidências de inventário local:
  - Apps Win32 (HKLM + WOW6432)
  - Apps Microsoft Store (Appx)
  - Serviços de terceiros (por caminho)
  - Serviços de terceiros em Auto-start
  - Tarefas agendadas fora de \Microsoft\
  - Startup do Registry (HKLM/HKCU Run)
  Gera CSVs por módulo + JSON consolidado e um log.
.NOTES
  Autor: Paulo (com apoio do ChatGPT)
  Execução recomendada: PowerShell como Administrador
#>

#region ====== Configurações ======
# Pausas guiadas entre fases
$Interactive = $true

# Saída: por padrão, usa Desktop real (OneDrive/Área de Trabalho etc.)
$Desktop = [Environment]::GetFolderPath('Desktop')
if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('MyDocuments') }

# Pasta de saída com timestamp
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = Join-Path $Desktop "Inventario-Windows11-$Timestamp"

# Cria pasta e log
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$LogPath = Join-Path $OutDir "inventario.log"

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  $line | Tee-Object -FilePath $LogPath -Append
}

function Pause-Step {
  param([string]$Message)
  if ($Interactive) {
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
    Read-Host "Pressione ENTER para continuar"
  }
}

function Assert-File {
  param([string]$Path)
  if (Test-Path $Path) {
    $fi = Get-Item $Path
    Write-Log "OK: arquivo gerado -> $($fi.Name) ($($fi.Length) bytes)"
  } else {
    Write-Log "ERRO: arquivo NÃO gerado -> $Path" "ERROR"
    throw "Falha ao gerar $Path"
  }
}

Write-Log "Início do inventário. Pasta de saída: $OutDir"
Write-Log "Desktop detectado: $Desktop"
#endregion

#region ====== Fase 1: Apps Win32 (HKLM + WOW6432) ======
Pause-Step "FASE 1 - Apps Win32 (HKLM + WOW6432). Objetivo: inventariar softwares instalados (visão tradicional) com campos auditáveis."

$AppsWin32Csv = Join-Path $OutDir "01_apps_win32.csv"

try {
  $apps1 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue
  $apps2 = Get-ItemProperty HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue

  ($apps1 + $apps2) |
    Where-Object { $_.DisplayName } |
    Select-Object `
      @{n="Name";e={$_.DisplayName}},
      @{n="Version";e={$_.DisplayVersion}},
      Publisher,
      InstallDate,
      InstallLocation,
      UninstallString,
      QuietUninstallString,
      PSChildName |
    Sort-Object Name |
    Export-Csv $AppsWin32Csv -NoTypeInformation -Encoding UTF8

  Assert-File $AppsWin32Csv
} catch {
  Write-Log "Falha na Fase 1: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 2: Apps Microsoft Store (Appx) ======
Pause-Step "FASE 2 - Apps Store (Appx). Objetivo: inventariar apps UWP/Microsoft Store que não aparecem no uninstall tradicional."

$AppsStoreCsv = Join-Path $OutDir "02_apps_store.csv"

try {
  Get-AppxPackage |
    Select-Object Name, Version, Publisher, InstallLocation |
    Sort-Object Name |
    Export-Csv $AppsStoreCsv -NoTypeInformation -Encoding UTF8

  Assert-File $AppsStoreCsv
} catch {
  Write-Log "Falha na Fase 2: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 3: Serviços de terceiros (por caminho) ======
Pause-Step "FASE 3 - Serviços de terceiros. Objetivo: mapear serviços não-Microsoft tipicamente instalados por apps (superfície de ataque)."

$ServicesCsv = Join-Path $OutDir "03_servicos_terceiros.csv"

try {
  Get-CimInstance Win32_Service |
    Where-Object { $_.PathName -match "Program Files|ProgramData|Users|WindowsApps" } |
    Select-Object Name, DisplayName, StartMode, State, StartName, PathName |
    Sort-Object DisplayName |
    Export-Csv $ServicesCsv -NoTypeInformation -Encoding UTF8

  Assert-File $ServicesCsv
} catch {
  Write-Log "Falha na Fase 3: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 4: Serviços Auto-start de terceiros ======
Pause-Step "FASE 4 - Serviços Auto-start. Objetivo: priorizar o que inicia sozinho (maior impacto/risco operacional)."

$ServicesAutoCsv = Join-Path $OutDir "04_servicos_auto_terceiros.csv"

try {
  Get-CimInstance Win32_Service |
    Where-Object {
      $_.StartMode -eq "Auto" -and
      $_.PathName -match "Program Files|ProgramData|Users|WindowsApps"
    } |
    Select-Object Name, DisplayName, State, StartName, PathName |
    Sort-Object DisplayName |
    Export-Csv $ServicesAutoCsv -NoTypeInformation -Encoding UTF8

  Assert-File $ServicesAutoCsv
} catch {
  Write-Log "Falha na Fase 4: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 5: Tarefas agendadas de terceiros ======
Pause-Step "FASE 5 - Tarefas agendadas de terceiros. Objetivo: identificar persistência/updates fora de \\Microsoft\\."

$TasksCsv = Join-Path $OutDir "05_tarefas_agendadas_terceiros.csv"

try {
  Get-ScheduledTask |
    Where-Object { $_.TaskPath -notmatch "\\Microsoft\\" } |
    Select-Object TaskName, TaskPath, State |
    Sort-Object TaskPath, TaskName |
    Export-Csv $TasksCsv -NoTypeInformation -Encoding UTF8

  Assert-File $TasksCsv
} catch {
  Write-Log "Falha na Fase 5: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 6: Startup (Registry Run HKLM/HKCU) ======
Pause-Step "FASE 6 - Startup Registry. Objetivo: mapear programas que iniciam com o Windows (persistência)."

$StartupCsv = Join-Path $OutDir "06_startup_registry.csv"

try {
  $startup = @()

  $hklm = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
  if ($hklm) {
    $startup += $hklm.PSObject.Properties |
      Where-Object { $_.Name -notmatch "^PS" } |
      Select-Object @{n="Scope";e={"HKLM-Run"}}, Name, @{n="Value";e={$_.Value}}
  }

  $hkcu = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
  if ($hkcu) {
    $startup += $hkcu.PSObject.Properties |
      Where-Object { $_.Name -notmatch "^PS" } |
      Select-Object @{n="Scope";e={"HKCU-Run"}}, Name, @{n="Value";e={$_.Value}}
  }

  $startup |
    Sort-Object Scope, Name |
    Export-Csv $StartupCsv -NoTypeInformation -Encoding UTF8

  Assert-File $StartupCsv
} catch {
  Write-Log "Falha na Fase 6: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion

#region ====== Fase 7: JSON consolidado + Resumo ======
Pause-Step "FASE 7 - Consolidar em JSON e gerar resumo. Objetivo: facilitar automação/análise por IA e manter um artefato único."

$JsonPath = Join-Path $OutDir "inventory_full.json"
$SummaryPath = Join-Path $OutDir "SUMMARY.txt"

try {
  $inv = [ordered]@{
    metadata = [ordered]@{
      generated_at = (Get-Date).ToString("s")
      computername = $env:COMPUTERNAME
      username     = $env:USERNAME
      outdir       = $OutDir
    }
    apps_win32   = Import-Csv $AppsWin32Csv
    apps_store   = Import-Csv $AppsStoreCsv
    services     = Import-Csv $ServicesCsv
    services_auto= Import-Csv $ServicesAutoCsv
    tasks        = Import-Csv $TasksCsv
    startup      = Import-Csv $StartupCsv
  }

  $inv | ConvertTo-Json -Depth 6 | Out-File $JsonPath -Encoding UTF8
  Assert-File $JsonPath

  $summary = @()
  $summary += "Inventário Windows 11 (GRC) - Resumo"
  $summary += "Gerado em: $(Get-Date)"
  $summary += "Pasta: $OutDir"
  $summary += ""
  $summary += "Contagens:"
  $summary += "Apps Win32      : $((Import-Csv $AppsWin32Csv).Count)"
  $summary += "Apps Store      : $((Import-Csv $AppsStoreCsv).Count)"
  $summary += "Serviços 3os    : $((Import-Csv $ServicesCsv).Count)"
  $summary += "Serviços Auto   : $((Import-Csv $ServicesAutoCsv).Count)"
  $summary += "Tarefas 3os     : $((Import-Csv $TasksCsv).Count)"
  $summary += "Startup Registry: $((Import-Csv $StartupCsv).Count)"
  $summary += ""
  $summary += "Arquivos gerados:"
  $summary += (Get-ChildItem $OutDir -File | Sort-Object Name | ForEach-Object { " - $($_.Name) ($($_.Length) bytes)" })

  $summary | Out-File $SummaryPath -Encoding UTF8
  Assert-File $SummaryPath

  Write-Log "Inventário concluído com sucesso."
  Write-Host ""
  Write-Host "✅ Inventário concluído!" -ForegroundColor Green
  Write-Host "📁 Saída: $OutDir"
  Write-Host "🧾 Resumo: $SummaryPath"
  Write-Host "🧠 JSON: $JsonPath"
} catch {
  Write-Log "Falha na Fase 7: $($_.Exception.Message)" "ERROR"
  throw
}
#endregion
