param(
    [string]$OutPath = "ui_snapshot.png",
    [int]$WaitMs = 2500
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$proc = Start-Process 'slint-viewer' -ArgumentList 'src/ui/app.slint' -PassThru
Start-Sleep -Milliseconds $WaitMs

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()

Stop-Process -Id $proc.Id -Force
Write-Host "[OK] Screenshot saved to: $OutPath"
