@echo off
rem Makes the pet start automatically when you log in to Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Desktop Pet.lnk'); $s.TargetPath='%~dp0Start-Pet.bat'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=7; $s.Save()"
call "%~dp0Start-Pet.bat"
echo Done! The pet starts with Windows and appears whenever Claude is open.
pause
