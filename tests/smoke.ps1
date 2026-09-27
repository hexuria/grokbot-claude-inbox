#Requires -Version 5.1
# Smoke test for skill/scripts/windows. Runs in a throwaway folder against a
# local fake webhook; touches nothing in your real ~/.grokbot.
#
# Usage: pwsh -File tests/smoke.ps1   (or powershell -File tests\smoke.ps1)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('grokbot-smoke-' + [Guid]::NewGuid().ToString('n').Substring(0, 8))
$home2 = Join-Path $tmp 'home'; $g = Join-Path $home2 '.grokbot'; $inbox = Join-Path $g 'inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null
Copy-Item (Join-Path $repo 'skill/scripts/windows/*.ps1') $g
$env:GROKBOT_HOME = $home2
$ps = (Get-Process -Id $PID).Path
$script:pass = 0; $script:fail = 0
function Check([string]$Name, [bool]$Ok) { if ($Ok) { $script:pass++; Write-Output "ok   $Name" } else { $script:fail++; Write-Output "FAIL $Name" } }
function Run { param([string]$Script, [string[]]$ScriptArgs, [string]$Stdin)
  $path = Join-Path $g $Script
  if ($PSBoundParameters.ContainsKey('Stdin')) { $out = $Stdin | & $ps -NoProfile -File $path @ScriptArgs 2>&1 } else { $out = & $ps -NoProfile -File $path @ScriptArgs 2>&1 }
  return @{ Code = $LASTEXITCODE; Out = ($out | ForEach-Object { "$_" }) -join "`n" }
}
function EnvVar([string]$File, [string]$Key) {
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $g $File))) { if ($l -match "^$Key='(.*)'$") { return $Matches[1].Replace("'\''", "'") } }
  return $null
}

# Fake webhook: records the last request; answers 500 under /fail.
$port = Get-Random -Minimum 20000 -Maximum 40000
$hook = Start-Job -ScriptBlock {
  param($port, $tmp)
  $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
  [IO.File]::WriteAllText((Join-Path $tmp 'ready'), 'ok')
  while ($true) {
    $ctx = $l.GetContext()
    $body = (New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
    [IO.File]::WriteAllText((Join-Path $tmp 'body'), $body, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $tmp 'auth'), "$($ctx.Request.Headers['Authorization'])")
    $code = if ($ctx.Request.Url.AbsolutePath -like '*/fail') { 500 } else { 200 }
    $ctx.Response.StatusCode = $code
    $bytes = [Text.Encoding]::UTF8.GetBytes('{"ok":' + $(if ($code -eq 200) { 'true' } else { 'false' }) + '}')
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
  }
} -ArgumentList $port, $tmp
$i = 0; while (-not (Test-Path (Join-Path $tmp 'ready')) -and $i -lt 100) { Start-Sleep -Milliseconds 100; $i++ }
if (-not (Test-Path (Join-Path $tmp 'ready'))) { Write-Output 'fake webhook did not start'; Receive-Job $hook; exit 1 }
function Body([string]$Field) { return (Get-Content -Raw (Join-Path $tmp 'body') | ConvertFrom-Json).$Field }

try {
  # --- ping ---------------------------------------------------------------
  [IO.File]::WriteAllText((Join-Path $g 'demo.env'), "WEBHOOK_URL='http://localhost:$port/hook'`nWEBHOOK_HEADER='Authorization: Bearer test-token'`nPROJECT='/tmp/demo'`nRULES='ask'`n")
  Check 'ping refuses an empty message'    ((Run 'ping.ps1' @('demo', 'decision', '-Message', '')).Code -eq 2)
  Check 'ping refuses an unknown need'     ((Run 'ping.ps1' @('demo', 'later', '-Message', 'hi')).Code -eq 2)
  Check 'ping refuses a non-kebab name'    ((Run 'ping.ps1' @('../demo', 'update', '-Message', 'hi')).Code -eq 2)
  Check 'ping refuses an unbound session'  ((Run 'ping.ps1' @('ghost', 'update', '-Message', 'hi')).Code -eq 2)
  Check 'ping refuses a missing need'      ((Run 'ping.ps1' @('demo', '-Message', 'hi')).Code -eq 2)

  $msg = "PR #12 is ready: `"quotes`", `$HOME, ``backticks``, ünïcødé 日本 🎉`nsecond line`twith a tab and back\slash"
  $r = Run 'ping.ps1' @('demo', 'pr_ready') $msg
  Check 'ping posts to the webhook (stdin)'   ($r.Code -eq 0)
  Check 'ping sends the Authorization header' ((Get-Content (Join-Path $tmp 'auth')) -eq 'Bearer test-token')
  Check 'ping sends session and need'         ((Body 'session') -eq 'demo' -and (Body 'need') -eq 'pr_ready')
  Check 'ping keeps the message byte for byte' ((Body 'message') -eq $msg)
  $r = Run 'ping.ps1' @('demo', 'update', '-Message', 'via parameter')
  Check 'ping accepts -Message'               ($r.Code -eq 0 -and (Body 'message') -eq 'via parameter')

  [IO.File]::WriteAllText((Join-Path $g 'down.env'), "WEBHOOK_URL='http://localhost:$port/fail'`nWEBHOOK_HEADER='Authorization: Bearer x'`n")
  $r = Run 'ping.ps1' @('down', 'update', '-Message', 'hi')
  Check 'ping fails loudly on a server error' ($r.Code -eq 22 -and $r.Out -like '*HTTP 500*')
  [IO.File]::WriteAllText((Join-Path $g 'mixed.env'), "WEBHOOK_URL='https://example.invalid/hook'`nWEBHOOK_HEADER='Authorization: Bearer https://example.invalid/hook'`n")
  $r = Run 'ping.ps1' @('mixed', 'update', '-Message', 'hi')
  Check 'ping refuses a header that holds the URL' ($r.Code -eq 2 -and $r.Out -like '*holds a URL*')
  [IO.File]::WriteAllText((Join-Path $g 'bare.env'), "WEBHOOK_URL='https://example.invalid/hook'`nWEBHOOK_HEADER='crsr_token_without_header_name'`n")
  Check 'ping refuses a header with no name'  ((Run 'ping.ps1' @('bare', 'update', '-Message', 'hi')).Code -eq 2)
  [IO.File]::WriteAllText((Join-Path $g 'swapped.env'), "WEBHOOK_URL='crsr_token_in_the_url_slot'`nWEBHOOK_HEADER='Authorization: Bearer x'`n")
  Check 'ping refuses a token in the URL slot' ((Run 'ping.ps1' @('swapped', 'update', '-Message', 'hi')).Code -eq 2)

  # --- bind ---------------------------------------------------------------
  $r = Run 'bind.ps1' @('bound') "WEBHOOK_URL='http://localhost:$port/hook'`nWEBHOOK_HEADER=`"Authorization: Bearer test-token`"`nPROJECT=/tmp/it's here`nRULES=merge-when-green`nROUTINE=claude-bound`n"
  Check 'bind writes the env file and pings'  ($r.Code -eq 0 -and (Test-Path (Join-Path $g 'bound.env')) -and (Test-Path (Join-Path $inbox 'bound.jsonl')))
  Check 'bind strips quotes and keeps apostrophes' ((EnvVar 'bound.env' 'WEBHOOK_HEADER') -eq 'Authorization: Bearer test-token' -and (EnvVar 'bound.env' 'PROJECT') -eq "/tmp/it's here" -and (EnvVar 'bound.env' 'ROUTINE') -eq 'claude-bound')
  Check 'bind writes LF line endings without a BOM' ((-not ([IO.File]::ReadAllText((Join-Path $g 'bound.env')).Contains("`r"))) -and ([IO.File]::ReadAllBytes((Join-Path $g 'bound.env'))[0] -eq [byte][char]'W'))
  Check 'bind sends the self-test ping'       ((Body 'message') -eq 'relay self-test' -and (Body 'session') -eq 'bound')
  $r = Run 'bind.ps1' @('bare2') "WEBHOOK_URL=http://localhost:$port/hook`nWEBHOOK_HEADER=crsr_bare_token`n"
  Check 'bind completes a bare token into a header' ((EnvVar 'bare2.env' 'WEBHOOK_HEADER') -eq 'Authorization: Bearer crsr_bare_token')
  $r = Run 'bind.ps1' @('bearer') "WEBHOOK_URL=http://localhost:$port/hook`nWEBHOOK_HEADER=Bearer crsr_x`n"
  Check 'bind completes a Bearer value into a header' ((EnvVar 'bearer.env' 'WEBHOOK_HEADER') -eq 'Authorization: Bearer crsr_x')
  $r = Run 'bind.ps1' @('same') "WEBHOOK_URL=https://x.invalid/h`nWEBHOOK_HEADER=https://x.invalid/h`n"
  Check 'bind refuses the same value twice'   ($r.Code -eq 2 -and -not (Test-Path (Join-Path $g 'same.env')))
  Check 'bind refuses unknown rules'          ((Run 'bind.ps1' @('rules') "WEBHOOK_URL=https://x.invalid/h`nWEBHOOK_HEADER=Authorization: Bearer x`nRULES=yolo`n").Code -eq 2)
  Check 'bind refuses a relative project path' ((Run 'bind.ps1' @('rel') "WEBHOOK_URL=https://x.invalid/h`nWEBHOOK_HEADER=Authorization: Bearer x`nPROJECT=relative/path`n").Code -eq 2)
  $r = Run 'bind.ps1' @('win') "WEBHOOK_URL=http://localhost:$port/hook`nWEBHOOK_HEADER=Authorization: Bearer x`nPROJECT=C:\Users\me\proj`n"
  Check 'bind accepts a Windows drive path'   ($r.Code -eq 0 -and (EnvVar 'win.env' 'PROJECT') -eq 'C:\Users\me\proj')
  Check 'bind refuses a line that is not KEY=VALUE' ((Run 'bind.ps1' @('junk') "garbage line`n").Code -eq 2)
  $r = Run 'bind.ps1' @('broken') "WEBHOOK_URL=http://localhost:$port/fail`nWEBHOOK_HEADER=Authorization: Bearer x`n"
  Check 'bind exits 1 when the self-test ping fails' ($r.Code -eq 1 -and (Test-Path (Join-Path $g 'broken.env')))
  if (Get-Command sh -ErrorAction SilentlyContinue) {
    $shRead = & sh -c ". '$g/bound.env'; printf '%s|%s' `"`$WEBHOOK_HEADER`" `"`$PROJECT`""
    Check 'the shell scripts can read an env file written by bind.ps1' ($shRead -eq "Authorization: Bearer test-token|/tmp/it's here")
  }

  # --- reply --------------------------------------------------------------
  Check 'reply refuses an unbound session'    ((Run 'reply.ps1' @('nobody', 'user', '-Message', 'hi')).Code -eq 2)
  [IO.File]::WriteAllText((Join-Path $inbox 'demo.jsonl'), '')
  Check 'reply refuses a bad sender'          ((Run 'reply.ps1' @('demo', 'boss', '-Message', 'hi')).Code -eq 2)
  $r = Run 'reply.ps1' @('demo', 'user', '-Message', 're PR #12 merge: approved')
  $lines = @([IO.File]::ReadAllLines((Join-Path $inbox 'demo.jsonl')))
  Check 'reply appends one JSON line'         ($r.Code -eq 0 -and $lines.Count -eq 1)
  $obj = $lines[0] | ConvertFrom-Json
  Check 'reply line has from, by, ts, session' ($obj.from -eq 'grokbot' -and $obj.by -eq 'user' -and $obj.session -eq 'demo' -and $lines[0] -match '"ts":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"' -and $obj.message -eq 're PR #12 merge: approved')

  # --- status -------------------------------------------------------------
  $demoInbox = Join-Path $inbox 'demo.jsonl'
  [IO.File]::WriteAllText((Join-Path $inbox 'demo.seen'), "$(@([IO.File]::ReadAllLines($demoInbox)).Count)`n")
  Run 'reply.ps1' @('demo', 'user', '-Message', 'one more') | Out-Null
  $row = ((Run 'status.ps1' @('demo')).Out -split "`n")[1] -split ' +'
  Check 'status shows listening, unread, webhook, rules, project' ($row[0] -eq 'demo' -and $row[1] -eq 'no' -and $row[2] -eq '1' -and $row[3] -eq 'ok' -and $row[5] -eq 'ask' -and $row[6] -eq '/tmp/demo')
  $tailExe = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) { (Get-Command tail -ErrorAction SilentlyContinue).Source } else { '/usr/bin/tail' }
  $listener = $null
  if ($tailExe) {
    $listener = Start-Process -FilePath $tailExe -ArgumentList @('-n', '0', '-F', $demoInbox) -PassThru -RedirectStandardOutput (Join-Path $tmp 'tail.out')
    Start-Sleep -Milliseconds 500
    $row = ((Run 'status.ps1' @('demo')).Out -split "`n")[1] -split ' +'
    Check 'status sees a running listener'      ($row[1] -eq 'yes')
  }
  Check 'status filters to one session'       ((((Run 'status.ps1' @('demo')).Out -split "`n").Count) -eq 2)
  $inboxes = @(Get-ChildItem -LiteralPath $inbox -Filter '*.jsonl' -File).Count
  Check 'status lists every inbox without a filter' ((((Run 'status.ps1' @()).Out -split "`n").Count) -eq ($inboxes + 1))

  # --- unbind -------------------------------------------------------------
  Check 'unbind refuses an unbound session'   ((Run 'unbind.ps1' @('nobody')).Code -eq 2)
  [IO.File]::WriteAllText((Join-Path $g 'demo.standing-prompt.txt'), 'prompt')
  $r = Run 'unbind.ps1' @('demo')
  Check 'unbind archives the inbox and removes the files' ($r.Code -eq 0 -and (@(Get-ChildItem (Join-Path $inbox 'archive') -Filter 'demo-*.jsonl').Count -eq 1) -and -not (Test-Path (Join-Path $inbox 'demo.jsonl')) -and -not (Test-Path (Join-Path $g 'demo.env')) -and -not (Test-Path (Join-Path $g 'demo.standing-prompt.txt')) -and -not (Test-Path (Join-Path $inbox 'demo.seen')))
  if ($listener) {
    Start-Sleep -Milliseconds 300
    Check 'unbind ends a running listener'    ($r.Out -like "*stopped Claude's listener*" -and $listener.HasExited)
  }
  $r = Run 'unbind.ps1' @('bound', '-Delete')
  Check 'unbind -Delete removes the inbox'    ($r.Code -eq 0 -and -not (Test-Path (Join-Path $inbox 'bound.jsonl')) -and (@(Get-ChildItem (Join-Path $inbox 'archive') -Filter 'bound-*.jsonl').Count -eq 0))
} finally {
  if ($listener -and -not $listener.HasExited) { Stop-Process -Id $listener.Id -Force -ErrorAction SilentlyContinue }
  Stop-Job $hook -ErrorAction SilentlyContinue; Remove-Job $hook -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output ''
Write-Output "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -ne 0) { exit 1 }
