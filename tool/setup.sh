#!/usr/bin/env bash
# One-time project setup. Run from anywhere:  bash tool/setup.sh
#
# android/ and ios/ are already configured and committed (bundle ids,
# permissions, signing, iPhone-only portrait), so there is no `flutter create`
# step. This script:
#   1. Installs packages.
#   2. Rebuilds the bundled content and icons (needs Pillow for images),
#      then installs launcher icons and the splash screen.
#   3. Runs the analyzer and tests.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Packages"
flutter pub get

echo "==> Content & icons"
if python3 -c "import PIL" 2>/dev/null; then
  python3 tool/build_content.py
  python3 tool/make_icon.py
else
  echo "   (Pillow not installed; using the committed assets)"
fi
dart run flutter_launcher_icons
dart run flutter_native_splash:create
# flutter_launcher_icons may rewrite this Xcode setting; restore it.
sed -i.bak 's/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;/' \
  ios/Runner.xcodeproj/project.pbxproj && rm -f ios/Runner.xcodeproj/project.pbxproj.bak

echo "==> Checks"
flutter analyze
flutter test

echo
echo "Done. Try it:  flutter run"
