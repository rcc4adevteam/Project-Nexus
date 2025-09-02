#!/bin/bash

# Generate a new keystore for Project Nexus
# This script creates a keystore file and updates key.properties

echo "Generating new keystore for Project Nexus..."

# Create keystore
keytool -genkey -v -keystore app/nexus-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias nexus_key \
  -storepass nexus123456 \
  -keypass nexus123456 \
  -dname "CN=Project Nexus, OU=Development, O=Your Company, L=Your City, S=Your State, C=Your Country"

if [ $? -eq 0 ]; then
    echo "Keystore generated successfully!"
    
    # Update key.properties
    cat > key.properties << EOF
storePassword=nexus123456
keyPassword=nexus123456
keyAlias=nexus_key
storeFile=app/nexus-release-key.jks
EOF
    
    echo "key.properties updated with new keystore information"
    echo ""
    echo "IMPORTANT: Keep this keystore file safe! You'll need it for future updates."
    echo "Keystore location: app/nexus-release-key.jks"
    echo "Password: nexus123456"
    echo "Alias: nexus_key"
    
else
    echo "Failed to generate keystore"
    exit 1
fi
