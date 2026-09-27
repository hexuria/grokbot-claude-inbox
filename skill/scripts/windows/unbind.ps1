#Requires -Version 5.1
# Unbind a session: stop its watcher, remove its env file, seen marker, lock,
# and standing prompt, and archive its inbox. The routine on Grok Bot is
# deleted separately.
#
# Usage: powershell -NoProfile -File $HOME\.grokbot\unbind.ps1 <session> [-Delete]
#   -Delete removes the inbox instead of archiving it.
param(
  [Parameter(Position = 0)][string]$Session,
  [switch]$Delete
)
$ErrorActionPreference = 'Stop'
function Fail([int]$Code, [string]$Text) { [Console]::Error.WriteLine("unbind: $Text"); exit $Code }

if (-not $Session) { Fail 2 'usage: unbind.ps1 <session> [-Delete]' }
if ($Session -notmatch '^[a-z0-9-]+$') { Fail 2 "session must be kebab-case, got '$Session'" }

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$g = Join-Path $base '.grokbot'; $d = Join-Path $g 'inbox'
$f = Join-Path $d "$Session.jsonl"; $envPath = Join-Path $g "$Session.env"
if (-not (Test-Path -LiteralPath $f) -and -not (Test-Path -LiteralPath $envPath)) { Fail 2 "'$Session' is not bound" }

$lock = Join-Path $d "$Session.lock"; $pidFile = Join-Path $lock 'pid'
if (Test-Path -LiteralPath $pidFile) {
  $raw = ([IO.File]::ReadAllText($pidFile)).Trim()
  if ($raw -match '^\d+$') {
    $proc = Get-Process -Id ([int]$raw) -ErrorAction SilentlyContinue
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Write-Output 'unbind: stopped the watcher' }
  }
}
foreach ($p in @($envPath, (Join-Path $g "$Session.standing-prompt.txt"), (Join-Path $d "$Session.seen"))) {
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
if (Test-Path -LiteralPath $lock) { Remove-Item -LiteralPath $lock -Recurse -Force }

if (Test-Path -LiteralPath $f) {
  if ($Delete) {
    Remove-Item -LiteralPath $f -Force; Write-Output "unbind: deleted $f"
  } else {
    $archive = Join-Path $d 'archive'; New-Item -ItemType Directory -Force -Path $archive | Out-Null
    $dest = Join-Path $archive ("$Session-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.jsonl')
    Move-Item -LiteralPath $f -Destination $dest -Force; Write-Output "unbind: archived the inbox to $dest"
  }
}
Write-Output "unbind: $Session is unbound; delete the routine `"Claude · $Session`" on Grok Bot"
