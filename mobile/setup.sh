#!/usr/bin/env bash
# Generates the Android/iOS platform folders (not committed) and applies Checkin's native config.
# Safe to re-run. Uses perl for edits so it behaves the same on macOS and Linux.
set -euo pipefail
cd "$(dirname "$0")"

flutter create . --project-name checkin_mobile --org com.machinenova --platforms=android,ios
flutter pub get

# edit FILE PERL-EXPR — in-place, whole-file regex edit.
edit() { perl -0pi -e "$2" "$1"; }

# ---------------- Android ----------------
manifest=android/app/src/main/AndroidManifest.xml

# Permissions: camera (Scan ID), network, biometric unlock.
for perm in CAMERA INTERNET USE_BIOMETRIC; do
  grep -q "android.permission.$perm\"" "$manifest" ||
    edit "$manifest" "s#(\\s*)<application#\$1<uses-permission android:name=\"android.permission.$perm\" />\$1<application#"
done

# App name; cleartext HTTP only matters for local dev against http:// APIs.
edit "$manifest" 's#android:label="checkin_mobile"#android:label="Checkin"#'
grep -q 'android:usesCleartextTraffic' "$manifest" ||
  edit "$manifest" 's#<application#<application android:usesCleartextTraffic="true"#'

# Offline data is encrypted with a device-bound key; don't ship the ciphertext to cloud backups.
grep -q 'android:allowBackup' "$manifest" ||
  edit "$manifest" 's#<application#<application android:allowBackup="false" android:fullBackupContent="false"#'

# Keystore-backed storage (flutter_secure_storage) needs Android 6.0+.
gradle=$(ls android/app/build.gradle* | head -1)
edit "$gradle" 's/minSdk(Version)?\s*=?\s*flutter\.minSdkVersion/minSdk = 23/'

# MainActivity: FlutterFragmentActivity (biometrics) + FLAG_SECURE (no screenshots / recents preview).
main=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
package=$(sed -n 's/^package \(.*\)$/\1/p' "$main")
sed "s/__PACKAGE__/$package/" android_template/MainActivity.kt > "$main"

# Release minification rules (ML Kit optional scripts).
cp android_template/proguard-rules.pro android/app/proguard-rules.pro
grep -q 'proguard-rules.pro' "$gradle" ||
  edit "$gradle" 's#(release \{\n)#$1            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n#'

# ---------------- iOS ----------------
plist=ios/Runner/Info.plist
grep -q NSCameraUsageDescription "$plist" ||
  edit "$plist" 's#<dict>#<dict>\n\t<key>NSCameraUsageDescription</key>\n\t<string>Scan voter ID cards to read the ID number.</string>#'
grep -q NSPhotoLibraryUsageDescription "$plist" ||
  edit "$plist" 's#<dict>#<dict>\n\t<key>NSPhotoLibraryUsageDescription</key>\n\t<string>Read the ID number from a photo of an ID card.</string>#'
# ML Kit (on-device ID reading) needs iOS 15.5+.
podfile=ios/Podfile
[ -f "$podfile" ] && edit "$podfile" "s/^#?\s*platform :ios, '[0-9.]+'/platform :ios, '15.5'/m"
grep -q NSFaceIDUsageDescription "$plist" ||
  edit "$plist" 's#<dict>#<dict>\n\t<key>NSFaceIDUsageDescription</key>\n\t<string>Unlock Checkin with Face ID.</string>#'

# ---------------- Icons ----------------
if [ -f ios/Runner.xcodeproj/project.pbxproj ]; then
  # Newer iOS templates ship without the legacy asset-catalog folder the icon tool writes into.
  mkdir -p ios/Runner/Assets.xcassets/AppIcon.appiconset
  dart run flutter_launcher_icons
else
  # No Xcode project on this machine (e.g. Intel Mac without Xcode): Android icons only.
  sed 's/^  ios: true/  ios: false/' pubspec.yaml | awk '/^flutter_launcher_icons:/{p=1} p&&/^[a-z]/&&!/^flutter_launcher_icons:/{p=0} p' > .icons-android.yaml
  dart run flutter_launcher_icons -f .icons-android.yaml
  rm -f .icons-android.yaml
fi

echo "Done. Run: flutter run --dart-define=API_URL=http://10.0.2.2:8080"
