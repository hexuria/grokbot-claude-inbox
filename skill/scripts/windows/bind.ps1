#Requires -Version 5.1
# Bind a session: write its env file from the routine's webhook URL and
# Authorization header, create its inbox, and prove the webhook with a
# self-test ping. Values are never printed, only their lengths.
#
# Usage:
#   powershell -NoProfile -File $HOME\.grokbot\bind.ps1 <session> -Dialog     two Windows dialogs ask for the values
#   @'
#   WEBHOOK_URL=https://...
#   WEBHOOK_HEADER=Authorization: Bearer ...
#   PROJECT=C:\absolute\path
#   RULES=ask
#   ROUTINE=claude-<session>
#   '@ | powershell -NoProfile -File $HOME\.grokbot\bind.ps1 <session>         or KEY=VALUE lines on stdin
#
# PROJECT, RULES and ROUTINE may also come in as environment variables.
param(
  [Parameter(Position = 0)][string]$Session,
  [switch]$Dialog
)
$ErrorActionPreference = 'Stop'
try { [Console]::InputEncoding = [Text.UTF8Encoding]::new($false); [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
function Fail([int]$Code, [string]$Text) { [Console]::Error.WriteLine("bind: $Text"); exit $Code }

if (-not $Session) { Fail 2 'usage: bind.ps1 <session> [-Dialog] (KEY=VALUE lines on stdin)' }
if ($Session -notmatch '^[a-z0-9-]+$') { Fail 2 "session must be kebab-case, got '$Session'" }

$url = "$env:WEBHOOK_URL"; $header = "$env:WEBHOOK_HEADER"
$project = "$env:PROJECT"; $rules = "$env:RULES"; $routine = "$env:ROUTINE"

if ($Dialog) {
  if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) { Fail 2 'dialog mode needs Windows; pipe KEY=VALUE lines instead' }
  Add-Type -AssemblyName System.Windows.Forms
  function Ask([string]$Prompt, [bool]$Hidden) {
    $form = New-Object Windows.Forms.Form
    $form.Text = 'grokbot-claude-inbox'; $form.Width = 560; $form.Height = 170
    $form.StartPosition = 'CenterScreen'; $form.TopMost = $true
    $label = New-Object Windows.Forms.Label
    $label.Text = "Session ${Session}: $Prompt"; $label.AutoSize = $true; $label.Left = 12; $label.Top = 12
    $box = New-Object Windows.Forms.TextBox
    $box.Left = 12; $box.Top = 40; $box.Width = 520; $box.UseSystemPasswordChar = $Hidden
    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'OK'; $ok.Left = 370; $ok.Top = 80; $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.Left = 455; $cancel.Top = 80; $cancel.DialogResult = 'Cancel'
    $form.AcceptButton = $ok; $form.CancelButton = $cancel
    $form.Controls.AddRange(@($label, $box, $ok, $cancel))
    if ($form.ShowDialog() -ne 'OK') { Fail 1 'dialog cancelled' }
    return $box.Text
  }
  $url = Ask "paste the routine's webhook URL" $false
  $header = Ask "paste the routine's full Authorization header" $true
} else {
  $text = [Console]::In.ReadToEnd()
  foreach ($raw in ("$text" -split "`n")) {
    $line = $raw.TrimEnd("`r")
    if ($line -match '^\s*(#|$)') { continue }
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
      $k = $Matches[1]; $v = $Matches[2]
      switch ($k) {
        'WEBHOOK_URL'    { $url = $v }
        'WEBHOOK_HEADER' { $header = $v }
        'PROJECT'        { $project = $v }
        'RULES'          { $rules = $v }
        'ROUTINE'        { $routine = $v }
        default          { Fail 2 "expected KEY=VALUE, got a line starting '$k'" }
      }
    } else { Fail 2 "expected KEY=VALUE, got a line starting '$($line.Split('=')[0])'" }
  }
}

# Trim whitespace, a stray carriage return, and one layer of quotes.
function Clean([string]$v) {
  $v = "$v".Replace("`r", '').Trim()
  if ($v -match "^'(.*)'$") { $v = $Matches[1] } elseif ($v -match '^"(.*)"$') { $v = $Matches[1] }
  return $v
}
$url = Clean $url; $header = Clean $header
$project = Clean $project; $rules = Clean $rules; $routine = Clean $routine

# Accept "Bearer <token>" or a bare token and complete the header.
if ($header -and $header -notmatch ': ') {
  if ($header -like 'Bearer *') { $header = "Authorization: $header" }
  elseif ($header -notmatch ' ') { $header = "Authorization: Bearer $header" }
}

if (-not $url) { Fail 2 'WEBHOOK_URL is empty' }
if (-not $header) { Fail 2 'WEBHOOK_HEADER is empty' }
if ($url -notmatch '^https?://') { Fail 2 'WEBHOOK_URL is not a URL' }
if ($header -match ' http|:http') { Fail 2 'WEBHOOK_HEADER holds a URL where the token belongs' }
if ($header -notmatch '^.+: .+$') { Fail 2 "WEBHOOK_HEADER must look like 'Authorization: Bearer <token>'" }
if ($url -eq $header) { Fail 2 'the URL and the header are the same value' }
if ($rules -and $rules -notin @('ask', 'merge-when-green')) { Fail 2 "RULES must be ask or merge-when-green, got '$rules'" }
if ($project -and $project -notmatch '^([A-Za-z]:[\\/]|/)') { Fail 2 "PROJECT must be an absolute path, got '$project'" }

function Q([string]$v) { return "'" + $v.Replace("'", "'\''") + "'" }
$base = if ($env:GROKBOT_HOME) { $env:GROKBOT_HOME } else { $HOME }
$g = Join-Path $base '.grokbot'; $inboxDir = Join-Path $g 'inbox'
$envPath = Join-Path $g "$Session.env"; $inbox = Join-Path $inboxDir "$Session.jsonl"
New-Item -ItemType Directory -Force -Path $inboxDir | Out-Null

$content = "WEBHOOK_URL=$(Q $url)`nWEBHOOK_HEADER=$(Q $header)`n"
if ($project) { $content += "PROJECT=$(Q $project)`n" }
if ($rules)   { $content += "RULES=$(Q $rules)`n" }
if ($routine) { $content += "ROUTINE=$(Q $routine)`n" }
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText("$envPath.tmp", $content, $utf8)
Move-Item -LiteralPath "$envPath.tmp" -Destination $envPath -Force
if (-not (Test-Path -LiteralPath $inbox)) { [IO.File]::WriteAllText($inbox, '', $utf8) }
Write-Output "bind: wrote $envPath (URL $($url.Length) chars, header $($header.Length) chars) and created the inbox"

# The self-test runs ping.ps1 as a child process, the way the relay runs it.
$psExe = (Get-Process -Id $PID).Path
& $psExe -NoProfile -File (Join-Path $g 'ping.ps1') $Session 'update' -Message 'relay self-test' | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Output "bind: self-test ping delivered; $Session is bound"
} else {
  [Console]::Error.WriteLine('bind: self-test ping failed, so the webhook is not proven; check the URL and header, then run bind again')
  exit 1
}
