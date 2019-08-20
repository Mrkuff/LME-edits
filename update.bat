@echo off
:: Credits: Credit to Ryan Watson (@gentlemanwatson) and Syspanda.com from which this script was adapted from.
:: Credit also to @S0xbad1dea for their input which has been merged here from https://github.com/ukncsc/lme/pull/4
:: Modified for 32 bit vs 64 bit, different install path and few security change Jonathan Martineau

:: Ive move the file inside the GPO instead of a dedicated structure in SYSVOL. GUID of GPO is set here
SET GUID={99999999-9999-9999-9999-999999999999}

:: Finding OS Architecture
:: https://support.microsoft.com/en-ca/help/556009
:: Not using %OS% because its already used
reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set NOS=32BIT || set NOS=64BIT
IF %NOS%==32BIT (
SET SYSMONBIN=Sysmon.exe
SET SIGCHECK=sigcheck.exe
) ELSE (
SET SYSMONBIN=Sysmon64.exe
SET SIGCHECK=sigcheck64.exe
)
ECHO %SYSMONBIN%
ECHO %SIGCHECK%
:: %~nI - Expands %I to a file name only. added for debug in command line FOR %i IN ("%SYSMONBIN%") DO (set PROCESS=%~nI)
FOR %%i IN ("%SYSMONBIN%") DO (set PROCESS=%%~nI)
ECHO %PROCESS%

:: Finding Domain FQDN
(wmic computersystem get domain | findstr /v Domain | findstr /r /v "^$") > %Windir%\Logs\fqdn.txt
SET /p FQDN=<%Windir%\Logs\fqdn.txt
SET FQDN=%FQDN: =%
ECHO %FQDN%

SET SYSMONCONF=sysmon.xml

:: Setting SYSVOL Path from GPO
SET GLBSYSMONBIN=\\%FQDN%\sysvol\%FQDN%\Policies\%GUID%\Machine\Scripts\%SYSMONBIN%
SET GLBSYSMONCONFIG=\\%FQDN%\sysvol\%FQDN%\Policies\%GUID%\Machine\Scripts\%SYSMONCONF%
SET GLBSIGCHECK=\\%FQDN%\sysvol\%FQDN%\Policies\%GUID%\Machine\Scripts\%SIGCHECK%

:: Is Sysmon running  
sc query %PROCESS% | find "STATE" | find "RUNNING"
IF "%ERRORLEVEL%" NEQ "0" (
:: No, lets try to start it
GOTO startsysmon
) ELSE (
:: Yes, Lets see if it needs updating
GOTO checkversion
)


:startsysmon
sc start %PROCESS%
IF "%ERRORLEVEL%" EQU "1060" (
:: Wont start, Lets install it
GOTO installsysmon
) ELSE (
:: Started, Lets see if it needs updating
GOTO checkversion
)


:installsysmon
:: Changing the directory for C:\windows\Sysmon since we install/reinstall
SET SYSMONDIR=C:\windows\Sysmon
IF Not EXIST %SYSMONDIR% (
mkdir %SYSMONDIR%
)
xcopy %GLBSYSMONBIN% %SYSMONDIR% /y
xcopy %GLBSYSMONCONFIG% %SYSMONDIR% /y
xcopy %GLBSIGCHECK% %SYSMONDIR% /y
chdir %SYSMONDIR%
:: We put the Logs in %Windir%\Logs\
echo "==========================================" >> %Windir%\Logs\SysmonInstall.log
echo %date% %time% >> %Windir%\Logs\SysmonInstall.log
%SYSMONBIN% -i %SYSMONCONF% -accepteula -h md5,sha256 -n -l >> %Windir%\Logs\SysmonInstall.log
echo "==========================================" >> %Windir%\Logs\SysmonInstall.log
:: We modified also the GPO for settings the service startup
sc config %PROCESS% start= auto
:: We exit here since we dont need to check or update it since its brand new
EXIT /B 0


:checkversion
:: Check if %SYSMONBIN% matches the hash of the central version 

:: Finding Installed Directory
(wmic process where "name='%SYSMONBIN%'" get ExecutablePath | findstr /v ExecutablePath) > %Windir%\Logs\path.txt
SET /p EXECUTABLEPATH=<%Windir%\Logs\path.txt
echo %EXECUTABLEPATH%
:: %~dpI - Expands %I to a drive letter and path only. added for debug in command line FOR %i IN ("%EXECUTABLEPATH%") DO (set SYSMONDIR=%~dpI)
FOR %%i IN ("%EXECUTABLEPATH%") DO (set SYSMONDIR=%%~dpI)
echo %SYSMONDIR%

chdir %SYSMONDIR%
:: We want to be sure it's the right %SIGCHECK% from SYSVOL
xcopy %GLBSIGCHECK% %SYSMONDIR% /y

(%SIGCHECK% -n -nobanner /accepteula %SYSMONBIN%) > %SYSMONDIR%\runningver.txt
(%SIGCHECK% -n -nobanner /accepteula %GLBSYSMONBIN%) > %SYSMONDIR%\latestver.txt
set /p runningver=<%SYSMONDIR%\runningver.txt
set /p latestver=<%SYSMONDIR%\latestver.txt
echo Currently running Sysmon : %runningver%
echo Latest sysmon is %latestver% located at %GLBSYSMONBIN%
IF "%runningver%" NEQ "%latestver%" (
GOTO uninstallsysmon
) ELSE (
GOTO updateconfig
)


:updateconfig
:: Added -c for the comparison, enables us to compare hashes
(%SIGCHECK% -h -c -nobanner /accepteula %SYSMONCONF%) > %SYSMONDIR%\runningconfver.txt
(%SIGCHECK% -h -c -nobanner /accepteula %GLBSYSMONCONFIG%) > %SYSMONDIR%\latestconfver.txt
::Looks for the 11th token in the csv of sigcheck. This is the MD5 hash. 12th token is SHA1, 15th is SHA2
:: added for debug in command line FOR /F "delims=, tokens=15" %h in (runningconfver.txt) DO (set runningconfver=%h)
FOR /F "delims=, tokens=15" %%h in (runningconfver.txt) DO (set runningconfver=%%h)
:: added for debug in command line FOR /F "delims=, tokens=15" %h in (latestconfver.txt) DO (set latestconfver=%h)
FOR /F "delims=, tokens=15" %%h in (latestconfver.txt) DO (set latestconfver=%%h)

IF "%runningconfver%" NEQ "%latestconfver%" (
xcopy %GLBSYSMONCONFIG% %SYSMONCONF% /y
%SYSMONBIN% -c %SYSMONCONF%
)
EXIT /B 0


:uninstallsysmon
echo "==========================================" >> %Windir%\Logs\SysmonUninstall.log
echo %date% %time% >> %Windir%\Logs\SysmonUninstall.log
%SYSMONBIN% -u >> %Windir%\Logs\SysmonUninstall.log
echo "==========================================" >> %Windir%\Logs\SysmonUninstall.log
IF EXIST runningver.txt DEL /F runningver.txt
IF EXIST latestver.txt DEL /F latestver.txt
IF EXIST runningconfver.txt DEL /F runningconfver.txt
IF EXIST latestconfver.txt DEL /F latestconfver.txt
IF EXIST %Windir%\Logs\fqdn.txt  DEL /F %Windir%\Logs\fqdn.txt
IF EXIST %Windir%\Logs\path.txt  DEL /F %Windir%\Logs\path.txt

GOTO installsysmon
