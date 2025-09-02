# Android Signing Configuration Guide

## Problem
You're encountering this build error:
```
Execution failed for task ':app:packageRelease'.
> A failure occurred while executing com.android.build.gradle.tasks.PackageAndroidArtifact$IncrementalSplitterRunnable
  > SigningConfig "release" is missing required property "storeFile".
```

## Root Cause
The release build is missing the required keystore file and signing configuration in `key.properties`.

## Solutions

### Solution 1: Quick Fix - Use Debug Signing (Recommended for Testing)
The `build.gradle` has been updated to fallback to debug signing if no keystore is configured.

**Pros:**
- Quick fix for testing
- No additional setup required
- Builds will work immediately

**Cons:**
- APK will be signed with debug certificate
- Not suitable for production releases
- Users can't update from Play Store

### Solution 2: Generate New Keystore (Recommended for Production)

#### For Windows Users:
1. Open Command Prompt in the `android` folder
2. Run: `generate_keystore.bat`
3. Follow the prompts

#### For Mac/Linux Users:
1. Open Terminal in the `android` folder
2. Run: `chmod +x generate_keystore.sh`
3. Run: `./generate_keystore.sh`

#### Manual Generation:
```bash
keytool -genkey -v -keystore app/nexus-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias nexus_key \
  -storepass nexus123456 \
  -keypass nexus123456 \
  -dname "CN=Project Nexus, OU=Development, O=Your Company, L=Your City, S=Your State, C=Your Country"
```

### Solution 3: Use Existing Keystore
If you have an existing keystore file:

1. Copy your keystore file to `android/app/`
2. Update `android/key.properties`:
```properties
storePassword=your_actual_password
keyPassword=your_actual_key_password
keyAlias=your_actual_alias
storeFile=app/your_keystore.jks
```

## File Structure After Fix
```
android/
├── key.properties          # Signing configuration
├── app/
│   ├── nexus-release-key.jks  # Keystore file
│   └── build.gradle
└── generate_keystore.sh   # Generation script
```

## Important Notes

### Security
- **NEVER commit keystore files to version control**
- **NEVER commit key.properties with real passwords**
- Keep your keystore file secure - you'll need it for future updates

### Production Releases
- Use a proper keystore for production releases
- Debug-signed APKs cannot be updated from Play Store
- Keystore must be the same for all updates of the same app

### Backup
- Backup your keystore file securely
- Losing the keystore means you can't update your app
- Consider using a password manager for keystore passwords

## Testing the Fix

### 1. Clean Build
```bash
flutter clean
flutter pub get
```

### 2. Build Release APK
```bash
flutter build apk --release
```

### 3. Verify Signing
```bash
jarsigner -verify -verbose -certs app/build/outputs/apk/release/app-release.apk
```

## Troubleshooting

### Common Issues

1. **"Keystore was tampered with"**
   - Check if keystore file is corrupted
   - Regenerate keystore

2. **"Wrong password"**
   - Verify passwords in key.properties
   - Check keystore file path

3. **"Alias not found"**
   - Verify keyAlias in key.properties
   - Check if alias exists in keystore

4. **"File not found"**
   - Verify storeFile path in key.properties
   - Check if keystore file exists

### Debug Commands

```bash
# List keystore contents
keytool -list -v -keystore app/nexus-release-key.jks

# Verify keystore integrity
keytool -verify -keystore app/nexus-release-key.jks

# Check build.gradle syntax
./gradlew assembleRelease --dry-run
```

## Next Steps

1. **Choose a solution** based on your needs
2. **Generate or configure keystore** using the provided scripts
3. **Test the build** with `flutter build apk --release`
4. **Verify signing** with `jarsigner -verify`
5. **Build your release APK** for distribution

## Support

If you continue to have issues:
1. Check the error messages carefully
2. Verify all file paths and passwords
3. Ensure keystore file is not corrupted
4. Try regenerating the keystore
5. Check Flutter and Gradle versions compatibility
