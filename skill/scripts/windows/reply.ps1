#Requires -Version 5.1
# Append a Grok Bot reply to a Claude Code session's inbox.
#
# Usage:
#   powershell -NoProfile -File $HOME\.grokbot\reply.ps1 <session> <user|relay> -Message "re <question>: <answer>"
#   "<message>" | powershell -NoProfile -File $HOME\.grokbot\reply.ps1 <session> <user|relay>
#
# user:  you are passing on the user's own answer.
# relay: you decided under the session's standing rules.
param(
  [Parameter(Position = 0)][string]$Session,
  [Parameter(Position = 1)][string]$By,
  [string]$Message
)
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
function Fail([int]$Code, [string]$Text) { [Console]::Error.WriteLine("reply: $Text"); exit $Code }

if (-not $Session -or -not $By) { Fail 2 'usage: reply.ps1 <session> <user|relay> [-Message <text>] (or the message on stdin)' }
if ($Session -notmatch '^[a-z0-9-]+$') { Fail 2 "session must be kebab-case, got '$Session'" }
if ($By -notin @('user', 'relay')) { Fail 2 "second argument must be user or relay, got '$By'" }

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$inbox = Join-Path (Join-Path (Join-Path $base '.grokbot') 'inbox') "$Session.jsonl"
if (-not (Test-Path -LiteralPath $inbox)) { Fail 2 "$inbox not found; '$Session' is not bound" }

if (-not $PSBoundParameters.ContainsKey('Message')) { $Message = [Console]::In.ReadToEnd() }
$Message = ("$Message" -replace "`r`n", "`n").TrimEnd("`n")
if ([string]::IsNullOrEmpty($Message)) { Fail 2 'empty message' }

$ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$line = [ordered]@{ session = $Session; from = 'grokbot'; by = $By; ts = $ts; message = $Message } | ConvertTo-Json -Compress
[IO.File]::AppendAllText($inbox, "$line`n", [Text.UTF8Encoding]::new($false))
$count = @([IO.File]::ReadAllLines($inbox)).Count
Write-Output "reply: wrote line $count of $inbox"
