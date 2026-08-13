# Windows twin of channel_status.sh — the winget and Chocolatey steps run on a
# windows runner under pwsh. Same contract: one tab-separated line per channel.
param(
    [Parameter(Mandatory = $true)][string]$Channel,
    [Parameter(Mandatory = $true)][ValidateSet('ok', 'skipped', 'failed')][string]$State,
    [string]$Detail = ''
)

$dir = if ($env:CHANNEL_STATUS_DIR) { $env:CHANNEL_STATUS_DIR } else { 'channel-status' }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# WriteAllText (not Out-File): the aggregator is a POSIX shell script, so the
# file must be plain UTF-8 with LF endings and no BOM.
$line = "$Channel`t$State`t$Detail`n"
[IO.File]::WriteAllText((Join-Path $dir "$Channel.tsv"), $line, (New-Object Text.UTF8Encoding $false))
