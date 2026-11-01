param(
    [string]$LaunchFlag = "true"
)

# Finish & Exit Installer
Stop-Process -Name "slint-viewer" -Force -ErrorAction SilentlyContinue
