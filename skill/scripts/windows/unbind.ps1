#Requires -Version 5.1
# Unbind a session: stop Claude's listener on its inbox, remove its env file,
# read cursor, and standing prompt, and archive its inbox. The routine on Grok Bot is
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

# Claude listens with its Monitor tool, which runs "tail -F" on the inbox.
# Returns one object per running tail (Id, CommandLine), or $null when the
# processes can't be listed.
function Get-TailProcesses {
  try {
    if ($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
      return @(Get-CimInstance Win32_Process -Filter "Name = 'tail.exe'" | ForEach-Object { [pscustomobject]@{ Id = [int]$_.ProcessId; CommandLine = "$($_.CommandLine)" } })
    }
    return @(& ps -Ao 'pid=,command=' 2>$null | ForEach-Object {
      $parts = "$_".Trim() -split '\s+', 2
      if ($parts.Count -eq 2 -and ($parts[1] -split '\s+')[0] -match '(^|/)tail$') { [pscustomobject]@{ Id = [int]$parts[0]; CommandLine = $parts[1] } }
    })
  } catch { return $null }
}
function Test-Listens([string]$CommandLine, [string]$Name) {
  return $CommandLine -match ('inbox[\\/]' + [regex]::Escape($Name) + '\.jsonl(\s|"|$)')
}

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$g = Join-Path $base '.grokbot'; $d = Join-Path $g 'inbox'
$f = Join-Path $d "$Session.jsonl"; $envPath = Join-Path $g "$Session.env"
if (-not (Test-Path -LiteralPath $f) -and -not (Test-Path -LiteralPath $envPath)) { Fail 2 "'$Session' is not bound" }

# Claude's Monitor runs "tail -F" on the inbox. Ending that tail ends the
# monitor, and Claude sees the env file is gone.
$stopped = $false
foreach ($t in @(Get-TailProcesses)) {
  if ($t -and (Test-Listens $t.CommandLine $Session)) { Stop-Process -Id $t.Id -Force -ErrorAction SilentlyContinue; $stopped = $true }
}
if ($stopped) { Write-Output "unbind: stopped Claude's listener" }
$lock = Join-Path $d "$Session.lock"
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
