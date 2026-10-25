@echo off
rem Runs preflight.ps1 without changing your PowerShell execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0preflight.ps1" %*
