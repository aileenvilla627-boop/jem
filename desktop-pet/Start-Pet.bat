@echo off
rem Starts the desktop pet in the background (no console window).
start "" powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0DesktopPet.ps1"
