param(
  [Parameter(Mandatory=$true)]
  [string]$InventoryFolder
)

$folder = (Resolve-Path $InventoryFolder).Path

function SafeImportCsv($p){ if(Test-Path $p){ Import-Csv $p } else { @() } }
function Clean($s){ if($null -eq $s){""} else { ($s -replace '"','').Trim() } }
function Now(){ (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

# === Load primary files ===
$svcAuto   = SafeImportCsv (Join-Path $folder "04_servicos_auto_terceiros.csv")
$tasks3p   = SafeImportCsv (Join-Path $folder "05_tarefas_agendadas_terceiros.csv")
$startup   = SafeImportCsv (Join-Path $folder "06_startup_registry.csv")
$appsWin32 = SafeImportCsv (Join-Path $folder "01_apps_win32.csv")
$appsStore = SafeImportCsv (Join-Path $folder "02_apps_store.csv")

function Classify-Action($name, $path){
  $n = ($name + " " + $path).ToLower()

  if($n -match "microsoft defender|windefend|mdcoresvc|securityhealth|intel\(r\)|realtek|nvidia driver|chipset|wslservice|officeclicktorun|click-to-run|visual c\+\+|\.net runtime|webview2"){
    return "KEEP (Base/Segurança/Driver)"
  }

  if($n -match "updater|update|telemetry|selfupdate|reporting|sync|onedrive|google updater|nvcontainer|logioptionsplus_updater|discord|steam|epicgames|gog|ea desktop|launcher"){
    return "REVIEW (Consumo/Background)"
  }

  if($n -match "rgb|lighting|gigabyte control center|easytune|techhub|peripheral manager"){
    return "CANDIDATE (Remover se não usa)"
  }

  return "REVIEW"
}

function Score-Persistence($startName, $path, $scope){
  $score = 0
  $isSystem = ($startName -match "(?i)localsystem|system|nt authority")
  $isMachine = ($path -match "(?i)\\program files\\|\\programdata\\|\\windows\\system32\\") -or ($scope -match "(?i)hklm")

  $score += 1 # persistente por definição (service/task/startup)
  if($isSystem){ $score += 1 }
  if($isMachine){ $score += 1 }

  return [pscustomobject]@{
    Score=$score; IsSystem=$isSystem; IsMachine=$isMachine
  }
}

$findings = @()

# Services (Auto 3os)
foreach($s in $svcAuto){
  $path = Clean $s.PathName
  $sc = Score-Persistence $s.StartName $path ""
  $findings += [pscustomobject]@{
    Type="Service(Auto)"
    Name=$s.Name
    DisplayName=$s.DisplayName
    StartName=$s.StartName
    Path=$path
    PersistenceScore=$sc.Score
    IsSystem=$sc.IsSystem
    IsMachine=$sc.IsMachine
    SuggestedAction=(Classify-Action $s.DisplayName $path)
  }
}

# Tasks (3os)
foreach($t in $tasks3p){
  $name = if ($t.TaskName) { $t.TaskName } elseif ($t.Name) { $t.Name } else { "" }
  $path = if ($t.TaskPath) { $t.TaskPath } else { "" }

  $findings += [pscustomobject]@{
    Type="ScheduledTask"
    Name=$name
    DisplayName=$name
    StartName=""
    Path=$path
    PersistenceScore=1
    IsSystem=$false
    IsMachine=$true
    SuggestedAction=(Classify-Action $name $path)
  }
}

# Startup registry
foreach($r in $startup){
  $scope = Clean $r.Scope
  $cmd   = Clean $r.Value
  $sc = Score-Persistence "" $cmd $scope

  $findings += [pscustomobject]@{
    Type="StartupRegistry"
    Name=(Clean $r.Name)
    DisplayName=(Clean $r.Name)
    StartName=""
    Path="$scope | $cmd"
    PersistenceScore=$sc.Score
    IsSystem=$false
    IsMachine=$sc.IsMachine
    SuggestedAction=(Classify-Action $r.Name $cmd)
  }
}

$topPersist = $findings |
  Sort-Object -Property @{Expression="PersistenceScore";Descending=$true}, Type, DisplayName |
  Select-Object -First 15

$topConsumo = $findings |
  Where-Object { $_.SuggestedAction -match "Consumo|CANDIDATE" } |
  Sort-Object -Property @{Expression="PersistenceScore";Descending=$true}, Type, DisplayName |
  Select-Object -First 20

$actions = $findings |
  Sort-Object SuggestedAction, @{Expression="PersistenceScore";Descending=$true}, Type, DisplayName

$outExec    = Join-Path $folder "EXEC_SUMMARY.md"
$outActions = Join-Path $folder "ACTIONS_recomendadas.csv"
$outPersist = Join-Path $folder "TOP_persistencia.csv"
$outConsumo = Join-Path $folder "TOP_consumo_suspeito.csv"

$actions    | Export-Csv $outActions -NoTypeInformation -Encoding UTF8
$topPersist | Export-Csv $outPersist -NoTypeInformation -Encoding UTF8
$topConsumo | Export-Csv $outConsumo -NoTypeInformation -Encoding UTF8

$svcCount = ($svcAuto | Measure-Object).Count
$taskCount = ($tasks3p | Measure-Object).Count
$startupCount = ($startup | Measure-Object).Count
$appsCount = ($appsWin32 | Measure-Object).Count
$storeCount = ($appsStore | Measure-Object).Count

$hot = $findings |
  Where-Object { $_.Type -eq "Service(Auto)" -and $_.IsSystem -and $_.IsMachine } |
  Select-Object -First 10

$md = @()
$md += "# Executive Summary – Inventário Local (Windows 11)"
$md += ""
$md += "**Gerado em:** $(Now)"
$md += "**Pasta:** $folder"
$md += ""
$md += "## Objetivo"
$md += "- Reduzir consumo e superfície de ataque **sem remover** jogos, Office, navegadores e ferramentas homologadas."
$md += "- Identificar componentes persistentes (serviços/tarefas/startup) que merecem decisão (manter, desativar, remover)."
$md += ""
$md += "## Panorama (tamanho do universo)"
$md += "- Apps Win32: $appsCount"
$md += "- Apps Store: $storeCount"
$md += "- Serviços Auto (3os): $svcCount"
$md += "- Tarefas (3os): $taskCount"
$md += "- Startup Registry: $startupCount"
$md += ""
$md += "## Síntese Executiva (o que importa)"
$md += "- O foco aqui é **eficiência e governança** (não é detecção de incidente)."
$md += "- O consumo/risco tende a se concentrar em poucos componentes persistentes."
$md += "- Priorizações: `TOP_persistencia.csv` e `TOP_consumo_suspeito.csv`."
$md += ""
$md += "## Decisão recomendada (3 níveis)"
$md += "- **KEEP:** base/driver/segurança (não mexer)."
$md += "- **REVIEW:** itens de background (avaliar se precisa iniciar junto com o Windows)."
$md += "- **CANDIDATE:** extras (RGB/gerenciadores) – remover se não usa."
$md += ""
$md += "## Hotspots (persistência + privilégio alto)"
$md += "Serviços Auto com escopo máquina e conta privilegiada:"
$md += ""
if(($hot | Measure-Object).Count -eq 0){
  $md += "- Nenhum hotspot identificado nesse critério."
} else {
  foreach($h in $hot){
    $md += "- $($h.DisplayName) | $($h.StartName) | $($h.Path)"
  }
}
$md += ""
$md += "## Próximo passo"
$md += "- Revisar em `ACTIONS_recomendadas.csv` apenas itens **CANDIDATE** e **REVIEW**."
$md += "- Aplicar mudanças em 2 ondas: (1) desativar startup/serviço não essencial, (2) remover (se validado)."

$md -join "`r`n" | Set-Content -Path $outExec -Encoding UTF8

Write-Host "OK. Gerados:" -ForegroundColor Green
Write-Host " - $outExec"
Write-Host " - $outActions"
Write-Host " - $outPersist"
Write-Host " - $outConsumo"
