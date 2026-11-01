@echo off
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = 'Select Sharabha Vessel Installation Directory'; $f.ShowNewFolderButton = $true; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Host $f.SelectedPath }"
