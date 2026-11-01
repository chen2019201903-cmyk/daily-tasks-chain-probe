#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# All output is project-local. Refuse to mix artifacts from an earlier build.
if [[ -e dist || -e build/DerivedData ]]; then
  echo 'Existing dist or build/DerivedData found. Use a fresh checkout for a new build.' >&2
  exit 1
fi
mkdir -p build/logs dist

{
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  sw_vers
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcrun swift --version
  git rev-parse HEAD
} | tee build/logs/environment.txt

node scripts/project.mjs --check
plutil -lint ChainProbe.xcodeproj/project.pbxproj Sources/App/Info.plist
python3 -B -m unittest discover -s Tests -p 'test_*.py' -v 2>&1 | tee build/logs/ipa-validator-tests.txt
xcrun swift test 2>&1 | tee build/logs/marker-tests.txt

run_number="${GITHUB_RUN_NUMBER:-1}"
run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
[[ "$run_number" =~ ^[0-9]+$ ]] && [[ "$run_attempt" =~ ^[0-9]+$ ]]

for variant in A B; do
  index=1
  [[ "$variant" == B ]] && index=2
  build_version="${run_number}.${run_attempt}.${index}"
  xcodebuild \
    -project ChainProbe.xcodeproj \
    -scheme ChainProbe \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    CURRENT_PROJECT_VERSION="$build_version" \
    PROBE_VARIANT="$variant" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    build 2>&1 | tee "build/logs/build-${variant}.txt"

  app='build/DerivedData/Build/Products/Release-iphoneos/ChainProbe.app'
  [[ -d "$app" ]]
  plutil -lint "$app/Info.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ProbeVariant' "$app/Info.plist")" == "$variant" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" == "$build_version" ]]
  lipo -verify_arch arm64 "$app/ChainProbe"
  if codesign -d "$app" >"build/logs/signature-${variant}.txt" 2>&1; then
    echo 'Unexpected signature. Refusing to call this an unsigned build.' >&2
    exit 1
  fi
  [[ ! -e "$app/embedded.mobileprovision" && ! -d "$app/_CodeSignature" ]]

  payload="build/package-${variant}/Payload"
  mkdir -p "$payload"
  ditto "$app" "$payload/ChainProbe.app"
  (cd "build/package-${variant}" && /usr/bin/zip -q -r "../../dist/ChainProbe-${variant}-unsigned.ipa" Payload)
  python3 scripts/verify-ipa.py "dist/ChainProbe-${variant}-unsigned.ipa" \
    --variant "$variant" --build "$build_version" \
    --report "dist/ChainProbe-${variant}-verification.json"
done

(cd dist && shasum -a 256 ./*.ipa > SHA256SUMS.txt)
cp build/logs/environment.txt dist/environment.txt
cp build/logs/marker-tests.txt dist/marker-tests.txt
cp docs/DEVICE-ACCEPTANCE.md dist/DEVICE-ACCEPTANCE.md
python3 - <<'PY'
import json, os, pathlib, subprocess
manifest = {
    'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'runURL': f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}",
    'minimumOS': '17.0',
    'bundleID': 'com.dailyhabit.chainprobe',
    'signing': 'unsigned; requires personal signing before installation',
    'deviceAcceptance': 'not performed by CI',
}
pathlib.Path('dist/build-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
echo 'A and B built and structurally verified. iPhone signing and device tests are still required.'
