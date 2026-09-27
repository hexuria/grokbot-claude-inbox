#Requires -Version 5.1
# Show each bound session: is a watcher listening, how many replies Claude has
# not read yet, whether its webhook env file exists, whether a Claude Code
# session is open for it, and its rules and project folder.
#
# Usage: powershell -NoProfile -File $HOME\.grokbot\status.ps1 [session]
param([Parameter(Position = 0)][string]$Session)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }

function Read-EnvFile([string]$Path) {
  $vars = @{}
  foreach ($raw in [IO.File]::ReadAllLines($Path)) {
    $line = $raw.TrimEnd("`r")
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
      $k = $Matches[1]; $v = $Matches[2]
      if ($v -match "^'(.*)'$") { $v = $Matches[1].Replace("'\''", "'") }
      elseif ($v -match '^"(.*)"$') { $v = $Matches[1] }
      $vars[$k] = $v
    }
  }
  return $vars
}

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$g = Join-Path $base '.grokbot'; $d = Join-Path $g 'inbox'

# Live Claude sessions, or $null when claude cannot be asked.
$live = $null
if (Get-Command claude -ErrorAction SilentlyContinue) {
  try {
    $text = (& claude agents --json 2>$null) -join "`n"
    $live = @($text | ConvertFrom-Json) | Where-Object { $_.state -ne 'done' -and $_.state -ne 'stopped' }
    $live = @($live)
  } catch { $live = @() }
}

$fmt = '{0,-20} {1,-8} {2,-7} {3,-8} {4,-7} {5,-17} {6}'
Write-Output ($fmt -f 'SESSION', 'WATCHER', 'UNREAD', 'WEBHOOK', 'CLAUDE', 'RULES', 'PROJECT')
if (-not (Test-Path -LiteralPath $d)) { exit 0 }
foreach ($file in (Get-ChildItem -LiteralPath $d -Filter '*.jsonl' -File | Sort-Object Name)) {
  $name = $file.BaseName
  if ($Session -and $name -ne $Session) { continue }

  $lines = if ($file.Length -eq 0) { 0 } else { @([IO.File]::ReadAllLines($file.FullName)).Count }
  $seen = 0; $seenPath = Join-Path $d "$name.seen"
  if (Test-Path -LiteralPath $seenPath) { $raw = ([IO.File]::ReadAllText($seenPath)).Trim(); if ($raw -match '^\d+$') { $seen = [int]$raw } }
  $unread = $lines - $seen; if ($unread -lt 0) { $unread = $lines }

  $pidFile = Join-Path (Join-Path $d "$name.lock") 'pid'
  $watcher = 'no'
  if ((Test-Path -LiteralPath $pidFile) -and (((Get-Date) - (Get-Item -LiteralPath $pidFile).LastWriteTime).TotalSeconds -lt 60)) { $watcher = 'yes' }

  $envPath = Join-Path $g "$name.env"; $project = ''; $rules = ''; $webhook = 'missing'
  if (Test-Path -LiteralPath $envPath) {
    $webhook = 'ok'; $vars = Read-EnvFile $envPath
    $project = "$($vars['PROJECT'])"; $rules = "$($vars['RULES'])"
  }

  $claude = '?'
  if ($null -ne $live) {
    $claude = '-'
    foreach ($a in $live) { if ($a.name -eq $name -or ($project -and $a.cwd -eq $project)) { $claude = 'open'; break } }
  }

  $rulesCol = if ($rules) { $rules } else { '-' }
  $projectCol = if ($project) { $project } else { '-' }
  Write-Output ($fmt -f $name, $watcher, $unread, $webhook, $claude, $rulesCol, $projectCol)
}
