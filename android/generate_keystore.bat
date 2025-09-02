@echo off
echo Generating new keystore for Project Nexus...

REM Create keystore
keytool -genkey -v -keystore app\nexus-release-key.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias nexus_key ^
  -storepass nexus123456 ^
  -keypass nexus123456 ^
  -dname "CN=Project Nexus, OU=Development, O=Your Company, L=Your City, S=Your State, C=Your Country"

if %ERRORLEVEL% EQU 0 (
    echo Keystore generated successfully!
    
    REM Update key.properties
    (
        echo storePassword=nexus123456
        echo keyPassword=nexus123456
        echo keyAlias=nexus_key
        echo storeFile=app/nexus-release-key.jks
    ) > key.properties
    
    echo key.properties updated with new keystore information
    echo.
    echo IMPORTANT: Keep this keystore file safe! You'll need it for future updates.
    echo Keystore location: app\nexus-release-key.jks
    echo Password: nexus123456
    echo Alias: nexus_key
) else (
    echo Failed to generate keystore
    pause
    exit /b 1
)

pause
