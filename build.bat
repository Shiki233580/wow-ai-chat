@echo off
setlocal
cd /d "%~dp0"
dotnet publish desktop\WhaleChat.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o dist
if errorlevel 1 exit /b 1
copy /y dist\WhaleChat.exe WhaleChat.exe >nul
if errorlevel 1 (
  echo Close the running WhaleChat tray process before replacing the EXE.
  exit /b 1
)
echo Built: %CD%\WhaleChat.exe
exit /b 0
