@echo off
setlocal
if exist "%~dp0\gradle\wrapper\gradle-wrapper.jar" (
  java -jar "%~dp0\gradle\wrapper\gradle-wrapper.jar" %*
) else (
  gradle %*
)
