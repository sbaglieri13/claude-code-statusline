[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$esc = [char]27

$iRobot = [char]::ConvertFromUtf32(0x1F916)  	# 🤖
$iFolder = [char]::ConvertFromUtf32(0x1F4C1)  	# 📁
$iLeaf = [char]::ConvertFromUtf32(0x1F33F)  	# 🌿
$iBrain = [char]::ConvertFromUtf32(0x1F9E0)  	# 🧠
$iFuel = [char]::ConvertFromUtf32(0x1F50B)   	# 🔋
$iTimer = [char]0x23F3                        	# ⏳
$iBullet = [char]0x2022                        	#  •
$iLightning = [char]0x26A1                      # ⚡

# Colors
$crail = "${esc}[38;2;193;95;60m"
$cloudy = "${esc}[38;2;177;173;161m"
$cyan = "${esc}[38;2;0;255;255m"
$red = "${esc}[38;2;255;85;85m"
$yellow = "${esc}[38;2;255;255;128m"
$green = "${esc}[38;2;80;250;123m"
$white = "${esc}[38;2;244;243;238m"
$reset = "${esc}[0m"

# Context bar color thresholds — set your thresholds here
function threshColor($pct) {
    if ($pct -lt 60) { return $green } elseif ($pct -lt 80) { return $yellow } else { return $red }
}
# Rate limit color thresholds — set your thresholds here
function usageColor($pct) {
    if ($pct -lt 70) { return $green } elseif ($pct -lt 95) { return $yellow } else { return $red }
}
function fmtTok([long]$n) {
    if ($n -ge 1000000) { return "$([math]::Round($n/1000000.0,1))M" }
    if ($n -ge 1000) { return "$([math]::Round($n/1000.0,0))k" }
    return "$n"
}
function fmtReset([long]$unixTs) {
    $en = [System.Globalization.CultureInfo]::new("en-US")
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($unixTs).LocalDateTime
    $diff = $dt - [DateTime]::Now
    if ($diff.TotalSeconds -le 0) { return 'now' }
    if ($diff.TotalHours -lt 24) { return $dt.ToString("h:mm tt", $en) }
    return $dt.ToString("MMM d, h:mm tt", $en)
}

$raw = $input | Out-String
$data = $null
try { $data = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue } catch {}

# MODEL
$mObj  = if ($data) { $data.model } else { $null }
$mName = if ($mObj -and $mObj.display_name) { [string]$mObj.display_name }
         elseif ($mObj -and $mObj.id) { [string]$mObj.id -replace '^claude-','' }
         elseif ($mObj) { [string]$mObj -replace '^claude-','' }
         else { 'Claude' }

# CONTEXT
$cw = if ($data) { $data.context_window } else { $null }
$totalTok = if ($cw -and $cw.context_window_size -and [long]$cw.context_window_size -gt 0) { [long]$cw.context_window_size }
            elseif ($cw -and $cw.total_tokens -and [long]$cw.total_tokens -gt 0) { [long]$cw.total_tokens }
            else { 200000L }
$usedTok = if ($cw -and $null -ne $cw.total_input_tokens) { [long]$cw.total_input_tokens + [long]$cw.total_output_tokens }
            elseif ($cw -and $cw.used_tokens) { [long]$cw.used_tokens }
            else { $null }
$usedPct = if ($cw -and $null -ne $cw.used_percentage) { [double]$cw.used_percentage }
            elseif ($null -ne $usedTok -and $totalTok -gt 0) { ($usedTok * 100.0) / $totalTok }
            else { 0.0 }

$pct = [int][math]::Min(100, [math]::Round($usedPct))
$tokenTotalStr = if ($null -ne $usedTok) { fmtTok($usedTok) } else { '0' }
$tokenLimitStr = fmtTok($totalTok)

# PROGRESS BAR
$barColor = threshColor($pct)
$barWidth = 10
$filled = [int][math]::Min([math]::Floor($pct / (100.0 / $barWidth)), $barWidth)
$barFull = [string][char]0x25CF   # ●
$barEmpty = [string][char]0x25CB  # ○
$bar = ($barColor + $barFull * $filled) + ($cloudy + $barEmpty * ($barWidth - $filled))

# RATE LIMITS
$rl = if ($data) { $data.rate_limits } else { $null }
$usageStr = ""; $resetStr = ""
if ($rl) {
    $uParts = @(); $rParts = @()
    if ($rl.five_hour -and $null -ne $rl.five_hour.used_percentage) {
        $p = [int]$rl.five_hour.used_percentage
        $uParts += "$(usageColor($p))${p}%${reset} ${cloudy}(Daily)"
        if ($rl.five_hour.resets_at) { $rParts += "${white}$(fmtReset([long]$rl.five_hour.resets_at)) ${cloudy}(Daily)" }
    }
    if ($rl.seven_day -and $null -ne $rl.seven_day.used_percentage) {
        $p = [int]$rl.seven_day.used_percentage
        $uParts += "$(usageColor($p))${p}%${reset} ${cloudy}(Weekly)"
        if ($rl.seven_day.resets_at) { $rParts += "${white}$(fmtReset([long]$rl.seven_day.resets_at)) ${cloudy}(Weekly)" }
    }
    if ($uParts.Count -gt 0) { $usageStr = "${cloudy}${iFuel} " + ($uParts -join " ${cloudy}${iBullet} ") + $reset }
    if ($rParts.Count -gt 0) { $resetStr = "${cloudy}${iTimer} Reset: " + ($rParts -join " ${cloudy}${iBullet} ") + $reset }
}

# FOLDER
$rawCwd = if ($data -and $data.cwd) { [string]$data.cwd } else { [string](Get-Location).Path }
$folder = Split-Path $rawCwd -Leaf

# GIT
$gitStatus = ""
if (Test-Path (Join-Path $rawCwd ".git")) {
    $branch = (git -C "$rawCwd" branch --show-current 2>$null)
    if ($branch) {
        $isDirty = (git -C "$rawCwd" status --short 2>$null)
        $gitColor = if ($isDirty) { $yellow } else { $green }
        $gitStatus = " ${cloudy}| ${gitColor}${iLeaf} $branch${reset}"
    }
}

# TIMER — from UserPromptSubmit hook timestamp to now (= true response time)
$timerStr = ""
try {
    $startMs = [long](Get-Content "$env:TEMP\claude-prompt-start.txt" -ErrorAction Stop)
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $deltaMs = $nowMs - $startMs
    if ($deltaMs -gt 500 -and $deltaMs -lt 600000) {
        $timerStr = " ${cloudy}| ${iLightning} $([math]::Round($deltaMs/1000.0,1))s${reset}"
    }
} catch {}

$ctxSection = "${barColor}${iBrain} Context ${bar}${barColor} ${pct}%${reset} ${cloudy}(${tokenTotalStr}/${tokenLimitStr})${reset}"

$line1 = "${cyan}${iRobot} $mName${reset} ${cloudy}| ${yellow}${iFolder} $folder${reset}${gitStatus}${timerStr}"
$line2 = "$ctxSection"
if ($usageStr) { $line2 += " ${cloudy}| $usageStr" }
if ($resetStr) { $line2 += " ${cloudy}| $resetStr" }

[Console]::Write("${line1}`n${line2}")
