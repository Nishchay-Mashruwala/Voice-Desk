@echo off
rem Double-click to install and build Voice Desk.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-windows.ps1" %*
