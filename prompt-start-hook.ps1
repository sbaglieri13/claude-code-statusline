[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() | Out-File "$env:TEMP\claude-prompt-start.txt" -Encoding utf8 -Force
