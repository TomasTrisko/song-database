@echo off
title Databaze pisnicek - Lokalni server
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
