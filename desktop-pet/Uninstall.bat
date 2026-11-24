@echo off
rem Stops the pet and removes the auto-start shortcut.
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Desktop Pet.lnk" 2>nul
powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*DesktopPet.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Pet stopped and auto-start removed.
pause
