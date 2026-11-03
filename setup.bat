@echo off
setlocal EnableExtensions
chcp 437 >nul
title Horizon - Setup and Repair Tool

rem ======================================================================
rem  Horizon Setup Tool
rem  Prepares Horizon the same way the manual steps do:
rem    1. finds the Horizon folder and your .minecraft folder
rem    2. checks Java 25
rem    3. downloads the official Minecraft server jar and verifies its SHA-1
rem    4. runs horizon-prepare --prepare, then the optional sounds step
rem    5. verifies the result and starts the game from the right folder
rem  Put this file inside the Horizon folder (next to horizon-prepare.exe)
rem  and double-click it. Change VER below if Horizon targets another version.
rem ======================================================================

set "VER=26.3"
set "TOTAL=6"
set "LOG=%TEMP%\horizon-fix-log.txt"
set "MC_ASKED="

rem --- ANSI colors (Windows 10 and newer) ---
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "C0=%ESC%[0m"
set "CR=%ESC%[91m"
set "CG=%ESC%[92m"
set "CY=%ESC%[93m"
set "CC=%ESC%[96m"
set "CW=%ESC%[97m"
set "CK=%ESC%[90m"

>"%LOG%" echo Horizon Setup log - %date% %time%
>>"%LOG%" echo Target Minecraft version: %VER%

cls
echo.
echo %CC%  ==========================================================%C0%
echo.
echo        %CW%H O R I Z O N%C0%  %CK%-  Setup Tool by perimaac%C0%
echo        %CK%Minecraft %VER% - Rust Edition%C0%
echo.
echo %CC%  ==========================================================%C0%
echo.
echo   This tool fixes the most common start-up problems by
echo   preparing Horizon's resources from your own Minecraft.
echo.
pause >nul

rem ----------------------------------------------------------------------
rem  Step 1: find Horizon
rem ----------------------------------------------------------------------
call :step 1 "Locating Horizon"
set "HZ=%~dp0"
if "%HZ:~-1%"=="\" set "HZ=%HZ:~0,-1%"
if exist "%HZ%\horizon-prepare.exe" goto :hz_ok

call :info "Not started from the Horizon folder. Searching for it..."
set "HZ="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-ChildItem -Path $env:LOCALAPPDATA,$env:APPDATA,($env:USERPROFILE+'\Downloads'),($env:USERPROFILE+'\Desktop') -Recurse -Filter horizon-prepare.exe -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty DirectoryName"`) do set "HZ=%%D"
if defined HZ goto :hz_ok

:ask_hz
call :warn "Could not find Horizon automatically."
echo.
echo    Drag your Horizon folder into this window and press Enter:
set "HZ="
set /p "HZ=   > "
if not defined HZ goto :fail_nohz
set HZ=%HZ:"=%
if "%HZ:~-1%"=="\" set "HZ=%HZ:~0,-1%"
if not exist "%HZ%\horizon-prepare.exe" goto :fail_nohz

:hz_ok
call :ok "Horizon folder: %HZ%"
if not exist "%HZ%\horizon-client.exe" call :warn "horizon-client.exe is missing in that folder."

rem ----------------------------------------------------------------------
rem  Step 2: find Minecraft
rem ----------------------------------------------------------------------
call :step 2 "Locating Minecraft %VER%"
set "MC=%APPDATA%\.minecraft"

:mc_check
if not exist "%MC%\versions\%VER%\%VER%.json" goto :mc_missing
if not exist "%MC%\versions\%VER%\%VER%.jar" goto :mc_missing
goto :mc_ok

:mc_missing
call :warn "Minecraft %VER% was not found in: %MC%"
if defined MC_ASKED goto :fail_nomc
set "MC_ASKED=1"
echo.
echo    If your game is in another place, drag that .minecraft folder here.
echo    Otherwise just press Enter, then install %VER% in the official
echo    Minecraft launcher, press Play once, and run this tool again.
set "MC_IN="
set /p "MC_IN=   > "
if not defined MC_IN goto :fail_nomc
set MC_IN=%MC_IN:"=%
if "%MC_IN:~-1%"=="\" set "MC_IN=%MC_IN:~0,-1%"
set "MC=%MC_IN%"
goto :mc_check

:mc_ok
call :ok "Minecraft folder: %MC%"

rem ----------------------------------------------------------------------
rem  Step 3: Java
rem ----------------------------------------------------------------------
call :step 3 "Checking Java (version 25 or newer)"
set "JV="
set "JMAJOR="
where java >nul 2>&1
if errorlevel 1 goto :java_missing
for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do if not defined JV set "JV=%%~v"
if not defined JV goto :java_missing
for /f "delims=." %%m in ("%JV%") do set "JMAJOR=%%m"
set /a JMN=%JMAJOR%+0
if %JMN% LSS 25 goto :java_old
call :ok "Java %JV% found"
goto :java_done

:java_missing
call :warn "Java was not found."
goto :java_help

:java_old
call :warn "Java %JV% is too old. Version 25 or newer is needed."

:java_help
echo    Download Java 25 from https://adoptium.net and run this tool again.
choice /c YN /n /m "   Continue anyway? [Y/N] "
if errorlevel 2 goto :done_fail

:java_done

rem ----------------------------------------------------------------------
rem  Step 4: server jar
rem ----------------------------------------------------------------------
call :step 4 "Getting the Minecraft %VER% server jar"
set "HZ_JSON=%MC%\versions\%VER%\%VER%.json"
set "SURL="
set "SSHA="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "$s=(Get-Content -Raw -LiteralPath $env:HZ_JSON | ConvertFrom-Json).downloads.server; if($s){$s.url;$s.sha1}"`) do if defined SURL (set "SSHA=%%L") else (set "SURL=%%L")
if not defined SSHA goto :fail_nojson

set "SJAR=%TEMP%\horizon-server-%VER%.jar"
set "GOT="
if exist "%SJAR%" call :gethash
if /i "%GOT%"=="%SSHA%" goto :jar_ok

call :info "Downloading the official server jar. Please wait..."
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -UseBasicParsing -Uri $env:SURL -OutFile $env:SJAR } catch { exit 1 }"
if errorlevel 1 goto :fail_download
call :gethash
if /i not "%GOT%"=="%SSHA%" goto :fail_hash

:jar_ok
call :ok "Server jar verified (SHA-1 matches Mojang)"

rem ----------------------------------------------------------------------
rem  Step 5: horizon-prepare
rem ----------------------------------------------------------------------
call :step 5 "Preparing Horizon resources (can take a few minutes)"
pushd "%HZ%"
echo.
"%HZ%\horizon-prepare.exe" --prepare --server-jar "%SJAR%" --minecraft-dir "%MC%"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto :fail_prepare
call :ok "Resources prepared"

call :info "Preparing sounds (optional)..."
echo.
"%HZ%\horizon-prepare.exe" sounds --minecraft-dir "%MC%"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" goto :sounds_warn
call :ok "Sounds prepared"
goto :sounds_done
:sounds_warn
call :warn "Sounds could not be prepared. The game still works, without sound."
:sounds_done

rem ----------------------------------------------------------------------
rem  Step 6: verify and launch
rem ----------------------------------------------------------------------
call :step 6 "Verifying the installation"
"%HZ%\horizon-prepare.exe" >nul 2>&1
if errorlevel 1 goto :fail_verify
call :ok "All required files verified"

if exist "%HZ%\resources\horizon-resources.json" goto :res_a
if exist "%HZ%\.local\horizon-client\%VER%\horizon-resources.json" goto :res_b
call :warn "Prepared resources were not found in the usual places."
goto :res_done
:res_a
call :ok "Resources folder: %HZ%\resources"
goto :res_done
:res_b
call :ok "Resources folder: %HZ%\.local\horizon-client\%VER%"
:res_done

del "%SJAR%" >nul 2>&1

echo.
echo %CG%  ==========================================================%C0%
echo.
echo        %CW%All done. Horizon is ready to play.%C0%
echo.
echo %CG%  ==========================================================%C0%
echo.
choice /c YN /n /m "   Start Horizon now? [Y/N] "
if errorlevel 2 goto :done_ok
start "" /D "%HZ%" "%HZ%\horizon-client.exe"
goto :done_ok

rem ----------------------------------------------------------------------
rem  Failures
rem ----------------------------------------------------------------------
:fail_nohz
call :bad "Horizon was not found."
echo    Put this file inside the Horizon folder, next to horizon-prepare.exe,
echo    and run it again.
goto :done_fail

:fail_nomc
call :bad "Minecraft %VER% files are missing."
echo    Install %VER% in the official Minecraft launcher, press Play once,
echo    close the game, and run this tool again.
goto :done_fail

:fail_nojson
call :bad "Could not read the server download from %VER%.json."
echo    Reinstall %VER% in the official Minecraft launcher and try again.
goto :done_fail

:fail_download
call :bad "The server jar could not be downloaded."
echo    Check your internet connection, antivirus or firewall, and try again.
goto :done_fail

:fail_hash
call :bad "The downloaded server jar does not match Mojang's checksum."
echo    Run this tool again. If it repeats, the download is being altered
echo    by a proxy, antivirus or network filter.
goto :done_fail

:fail_prepare
call :bad "horizon-prepare failed (exit code %RC%)."
echo    Read the message printed above. Take a screenshot of it and send it
echo    together with the log file shown below.
goto :done_fail

:fail_verify
call :bad "Verification failed: some prepared files are missing or changed."
echo    Run this tool again. If it repeats, send the log file shown below.
goto :done_fail

:done_fail
echo.
echo %CR%  Setup did not finish.%C0%
echo %CK%  Log file: %LOG%%C0%
echo.
popd >nul 2>&1
pause
exit /b 1

:done_ok
echo.
echo %CK%  If the game still crashes, send the crash report and this log:%C0%
echo %CK%  %LOG%%C0%
echo.
popd >nul 2>&1
pause
exit /b 0

rem ----------------------------------------------------------------------
rem  Helpers
rem ----------------------------------------------------------------------
:step
echo.
echo %CC%  [%~1/%TOTAL%]%C0% %CW%%~2%C0%
>>"%LOG%" echo.
>>"%LOG%" echo [step %~1/%TOTAL%] %~2
exit /b

:ok
echo     %CG%[ OK ]%C0% %~1
>>"%LOG%" echo   [OK] %~1
exit /b

:warn
echo     %CY%[ !! ]%C0% %~1
>>"%LOG%" echo   [WARN] %~1
exit /b

:bad
echo     %CR%[FAIL]%C0% %~1
>>"%LOG%" echo   [FAIL] %~1
exit /b

:info
echo     %CK%[ .. ]%C0% %~1
>>"%LOG%" echo   [info] %~1
exit /b

:gethash
set "GOT="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA1 -LiteralPath $env:SJAR).Hash.ToLower()"`) do set "GOT=%%H"
exit /b
