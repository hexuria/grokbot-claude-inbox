#Requires -Version 5.1
# Wait for the next unread lines in a session's inbox, print them, and exit.
# Claude Code runs this as a background command and starts it again whenever
# it exits. After WATCH_LIMIT seconds (default 1500) with nothing new it exits
# with no output.
#
# Usage: powershell -NoProfile -File $HOME\.grokbot\watch.ps1 <session>
param([Parameter(Position = 0)][string]$Session)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
function Fail([int]$Code, [string]$Text) { [Console]::Error.WriteLine("watch: $Text"); exit $Code }

if (-not $Session) { Fail 2 'usage: watch.ps1 <session>' }
if ($Session -notmatch '^[a-z0-9-]+$') { Fail 2 "session must be kebab-case, got '$Session'" }

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$d = Join-Path (Join-Path $base '.grokbot') 'inbox'
$f = Join-Path $d "$Session.jsonl"; $s = Join-Path $d "$Session.seen"
$lock = Join-Path $d "$Session.lock"; $pidFile = Join-Path $lock 'pid'
$limit = if ($env:WATCH_LIMIT) { [int]$env:WATCH_LIMIT } else { 1500 }
if (-not (Test-Path -LiteralPath $f)) { Fail 2 "$f not found; '$Session' is not bound" }

function Count-Lines {
  if ((Get-Item -LiteralPath $f).Length -eq 0) { return 0 }
  return @([IO.File]::ReadAllLines($f)).Count
}
function Lock-IsFresh {
  if (-not (Test-Path -LiteralPath $pidFile)) { return $false }
  return ((Get-Date) - (Get-Item -LiteralPath $pidFile).LastWriteTime).TotalSeconds -lt 60
}

# One watcher per inbox. The watcher touches its pid file every few seconds;
# a lock whose pid file is older than a minute belongs to a dead watcher and
# is taken over. Shell and PowerShell watchers share this rule.
try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null }
catch {
  if (Lock-IsFresh) { Fail 1 "a watcher for $Session is already running" }
  Remove-Item -LiteralPath $lock -Recurse -Force
  New-Item -ItemType Directory -Path $lock | Out-Null
}
[IO.File]::WriteAllText($pidFile, "$PID`n")

try {
  # Resume after the last line printed. Start over if the inbox was replaced
  # by a shorter file.
  $n = 0
  if (Test-Path -LiteralPath $s) { $raw = ([IO.File]::ReadAllText($s)).Trim(); if ($raw -match '^\d+$') { $n = [int]$raw } }
  if ($n -gt (Count-Lines)) { $n = 0 }

  $waited = 0
  while ((Count-Lines) -le $n) {
    if ($waited -ge $limit) { exit 0 }
    Start-Sleep -Seconds 5; $waited += 5
    (Get-Item -LiteralPath $pidFile).LastWriteTime = Get-Date
  }

  $lines = @([IO.File]::ReadAllLines($f))
  for ($i = $n; $i -lt $lines.Count; $i++) {
    $n++
    if ($lines[$i]) { Write-Output "grokbot inbox #${n}: $($lines[$i])" }
    [IO.File]::WriteAllText("$s.tmp", "$n`n")
    Move-Item -LiteralPath "$s.tmp" -Destination $s -Force
  }
} finally {
  Remove-Item -LiteralPath $lock -Recurse -Force -ErrorAction SilentlyContinue
}
