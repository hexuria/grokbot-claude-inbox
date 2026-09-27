#Requires -Version 5.1
# Send a message from a Claude Code session to its Grok Bot webhook routine.
#
# Usage:
#   powershell -NoProfile -File $HOME\.grokbot\ping.ps1 <session> <need> -Message "<message>"
#   "<message>" | powershell -NoProfile -File $HOME\.grokbot\ping.ps1 <session> <need>
#
# need: decision | merge | pr_ready | recap | update | blocker
# Reads WEBHOOK_URL and WEBHOOK_HEADER from $HOME\.grokbot\<session>.env.
param(
  [Parameter(Position = 0)][string]$Session,
  [Parameter(Position = 1)][string]$Need,
  [string]$Message
)
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
function Fail([int]$Code, [string]$Text) { [Console]::Error.WriteLine("ping: $Text"); exit $Code }

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

if (-not $Session -or -not $Need) { Fail 2 'usage: ping.ps1 <session> <need> [-Message <text>] (or the message on stdin)' }
if ($Session -notmatch '^[a-z0-9-]+$') { Fail 2 "session must be kebab-case, got '$Session'" }
if ($Need -notin @('decision', 'merge', 'pr_ready', 'recap', 'update', 'blocker')) { Fail 2 "unknown need '$Need'" }

$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$envFile = Join-Path (Join-Path $base '.grokbot') "$Session.env"
if (-not (Test-Path -LiteralPath $envFile)) { Fail 2 "$envFile not found; '$Session' is not bound" }
$vars = Read-EnvFile $envFile
$url = "$($vars['WEBHOOK_URL'])"; $header = "$($vars['WEBHOOK_HEADER'])"
if (-not $url -or -not $header) { Fail 2 "$envFile needs WEBHOOK_URL and WEBHOOK_HEADER" }
if ($url -notmatch '^https?://') { Fail 2 "WEBHOOK_URL in $envFile is not a URL" }
if ($header -match ' http|:http') { Fail 2 "WEBHOOK_HEADER in $envFile holds a URL where the token belongs" }
if ($header -notmatch '^.+: .+$') { Fail 2 "WEBHOOK_HEADER in $envFile must look like 'Authorization: Bearer <token>'" }

if (-not $PSBoundParameters.ContainsKey('Message')) { $Message = [Console]::In.ReadToEnd() }
$Message = ("$Message" -replace "`r`n", "`n").TrimEnd("`n")
if ([string]::IsNullOrEmpty($Message)) { Fail 2 'empty message' }

$i = $header.IndexOf(': ')
$headers = @{ $header.Substring(0, $i) = $header.Substring($i + 2) }
$json = [ordered]@{ session = $Session; need = $Need; message = $Message } | ConvertTo-Json -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($json)

try {
  $resp = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $url -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30
  if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { "$($resp.Content)" }
  exit 0
} catch {
  $status = ''; $body = ''
  try { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } } catch { }
  try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $body = $_.ErrorDetails.Message } } catch { }
  if (-not $body) { try { $stream = $_.Exception.Response.GetResponseStream(); if ($stream) { $body = (New-Object IO.StreamReader($stream)).ReadToEnd() } } catch { } }
  if ($status) { Fail 22 "the webhook returned HTTP $status $body" } else { Fail 7 "the request failed: $($_.Exception.Message)" }
}
