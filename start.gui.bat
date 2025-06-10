@echo off
powershell -WindowStyle Hidden -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0server-manager\\server-manager.ps1\"' -Verb RunAs"
