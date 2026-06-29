@echo off
setlocal

set "ASHITA_ROOT=%~dp0"
set "ASHITA_CLI=%ASHITA_ROOT%Ashita-cli.exe"
set "ACCESSXI_PROFILE_NAME=accessxi-retail.ini"
set "ACCESSXI_PROFILE=%ASHITA_ROOT%config\boot\%ACCESSXI_PROFILE_NAME%"
set "ACCESSXI_LAUNCH_LOG=%ASHITA_ROOT%logs\accessxi-launch.log"

if not exist "%ASHITA_ROOT%logs" mkdir "%ASHITA_ROOT%logs"
>> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] AccessXI launcher starting from "%ASHITA_ROOT%".

if not exist "%ASHITA_CLI%" (
    >> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] ERROR missing "%ASHITA_CLI%".
    echo AccessXI launch failed: Ashita-cli.exe was not found in "%ASHITA_ROOT%".
    pause
    exit /b 1
)

if not exist "%ACCESSXI_PROFILE%" (
    >> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] ERROR missing "%ACCESSXI_PROFILE%".
    echo AccessXI launch failed: config\boot\accessxi-retail.ini was not found in "%ASHITA_ROOT%".
    pause
    exit /b 1
)

>> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] Launching "%ASHITA_CLI%" "%ACCESSXI_PROFILE_NAME%".
pushd "%ASHITA_ROOT%"
if ERRORLEVEL 1 (
    >> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] ERROR could not enter "%ASHITA_ROOT%".
    echo AccessXI launch failed: could not enter "%ASHITA_ROOT%".
    pause
    exit /b 1
)

"%ASHITA_CLI%" "%ACCESSXI_PROFILE_NAME%"
set "ACCESSXI_EXIT=%ERRORLEVEL%"
popd
>> "%ACCESSXI_LAUNCH_LOG%" echo [%DATE% %TIME%] Ashita-cli exited %ACCESSXI_EXIT%.
exit /b %ACCESSXI_EXIT%
