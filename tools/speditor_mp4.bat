@echo off
rem SPeditor / SAeditor: turns rendered videos into small MP4 files (H.264 video, AAC sound).
rem
rem The game can only write MJPEG video and gives addons no way to run an H.264 encoder,
rem so <name>.avi.dat files are large. This script re-encodes each of them into <name>.mp4
rem next to it, the sound track is kept. Needs ffmpeg.exe in PATH or next to this file.
rem
rem   speditor_mp4.bat              all videos in garrysmod\data\speditor\renders
rem   speditor_mp4.bat <folder>     all videos in another folder
rem   speditor_mp4.bat --watch      stay running and convert every video once it is rendered
setlocal enabledelayedexpansion
set "WATCH=0"
if "%~1"=="--watch" (
	set "WATCH=1"
	shift
)
set "DIR=%~1"
if "%DIR%"=="" set "DIR=%~dp0..\..\..\data\speditor\renders"
if "%CRF%"=="" set "CRF=18"
set "PATH=%~dp0;%PATH%"
where ffmpeg >nul 2>nul
if errorlevel 1 (
	echo ffmpeg is not installed: put ffmpeg.exe next to this file or add it to PATH
	exit /b 1
)
if "%WATCH%"=="1" echo watching %DIR% (Ctrl+C to stop)

:again
for %%F in ("%DIR%\*.avi.dat" "%DIR%\*.avi") do call :convert "%%~fF"
if "%WATCH%"=="1" (
	timeout /t 2 /nobreak >nul
	goto again
)
exit /b 0

:convert
set "SRC=%~1"
set "OUT=%SRC%"
if /i "%OUT:~-4%"==".dat" set "OUT=%OUT:~0,-4%"
set "OUT=%OUT:~0,-4%.mp4"
rem skip a video whose .mp4 is newer (the newest of the two files comes first)
if exist "%OUT%" (
	set "NEWEST="
	for /f "delims=" %%N in ('dir /b /o-d "%SRC%" "%OUT%" 2^>nul') do if not defined NEWEST set "NEWEST=%%N"
	rem an .mp4 whose conversion was cut short has no index: it is made again
	set "BROKEN=0"
	where ffprobe >nul 2>nul && ffprobe -v error -show_entries format^=duration -of csv^=p^=0 "%OUT%" >nul 2>nul || set "BROKEN=1"
	where ffprobe >nul 2>nul || set "BROKEN=0"
	for %%O in ("%OUT%") do if /i "!NEWEST!"=="%%~nxO" if "!BROKEN!"=="0" exit /b 0
)
rem a file the editor still writes to is locked or has no index yet: ffmpeg fails and it is tried again later
ffmpeg -v error -y -f avi -i "%SRC%" -c:v libx264 -preset slow -crf %CRF% -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a aac -b:a 192k -movflags +faststart "%OUT%.part.mp4"
if errorlevel 1 (
	del "%OUT%.part.mp4" >nul 2>nul
	if "%WATCH%"=="0" echo could not convert %~nx1 ^(still being rendered?^)
	exit /b 0
)
move /y "%OUT%.part.mp4" "%OUT%" >nul
echo %~nx1 -^> %OUT%
exit /b 0
