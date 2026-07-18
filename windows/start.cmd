@echo off
REM Wrapper for sandbox.ps1 — bypasses PowerShell execution policy.
REM Usage: windows\start.cmd tools | up | verify | status | stop | clean
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sandbox.ps1" %*
