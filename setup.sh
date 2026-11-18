#!/usr/bin/env bash
# Adds the Android, iOS and web platform folders and applies the settings
# Firebase needs on each. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed: https://docs.flutter.dev/get-started/install"
  exit 1
fi

# Creates only missing files; your lib/, pubspec.yaml and test/ are kept.
flutter create --platforms=android,ios,web --org ng.duespay --project-name duespay .
flutter pub get

# Android: release builds need INTERNET in the main manifest
# (Flutter's template only adds it to the debug manifest).
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ] && ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.INTERNET"\/>/' "$MANIFEST"
  echo "Android: added INTERNET permission."
fi

# iOS: current Firebase SDKs need iOS 15 or later.
PBXPROJ=ios/Runner.xcodeproj/project.pbxproj
if [ -f "$PBXPROJ" ]; then
  perl -pi -e 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' "$PBXPROJ"
  echo "iOS: deployment target set to 15.0."
fi
if [ -f ios/Podfile ]; then
  perl -pi -e "s/^\s*#?\s*platform :ios.*/platform :ios, '15.0'/" ios/Podfile
fi

# Web: proper tab title instead of the package name.
if [ -f web/index.html ]; then
  perl -0pi -e 's#<title>.*?</title>#<title>DuesPay</title>#s' web/index.html
  perl -0pi -e 's#(<meta name="description" content=")[^"]*#${1}Collect student dues by bank transfer.#' web/index.html
fi
if [ -f web/manifest.json ]; then
  perl -pi -e 's/"name": "[^"]*"/"name": "DuesPay"/; s/"short_name": "[^"]*"/"short_name": "DuesPay"/' web/manifest.json
fi

cat <<'EOF'

Platforms ready. Next:
  dart pub global activate flutterfire_cli
  flutterfire configure --platforms=android,ios,web
Then run on any device:
  flutter run --dart-define=BACKEND_URL=https://your-project.vercel.app
EOF
