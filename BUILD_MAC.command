#!/bin/bash
# OurTibia - builds the macOS client (OurTibia.app) on a Mac.
# Usage: double-click this file in Finder, or in Terminal:
#   ./BUILD_MAC.command                       (game data downloaded from ourtibia.com)
#   ./BUILD_MAC.command /path/OurTibia-Linux.tar.gz   (game data from a local file)
# Result: out/OurTibia-macOS-<arch>.zip  (send this file back)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/OurTibia-mac-build"
OUT="$HERE/out"
LOG="$OUT/build.log"
DATA_URL="https://ourtibia.com/downloads/OurTibia-Linux.tar.gz"
mkdir -p "$WORK" "$OUT"
exec > >(tee "$LOG") 2>&1

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n(full log: %s)\n' "$*" "$LOG"; exit 1; }

[ "$(uname)" = "Darwin" ] || die "this script runs only on macOS"

say "1/7 Apple Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  die "Install the Command Line Tools in the window that opened, then run this script again."
fi

say "2/7 Homebrew tools"
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
fi
command -v brew >/dev/null 2>&1 || die "Homebrew is missing. Install it from https://brew.sh (one command), then run this script again."
brew install cmake ninja pkg-config autoconf autoconf-archive automake libtool nasm >/dev/null
for t in cmake ninja pkg-config; do command -v "$t" >/dev/null || die "$t not found after brew install"; done

ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  TRIPLET=arm64-osx ;;
  x86_64) TRIPLET=x64-osx ;;
  *) die "unknown CPU: $ARCH" ;;
esac
echo "CPU: $ARCH  (vcpkg triplet $TRIPLET)"

say "3/7 vcpkg (libraries - the first build takes 30-60 minutes)"
export VCPKG_ROOT="$WORK/vcpkg"
if [ ! -d "$VCPKG_ROOT/.git" ]; then
  git clone https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
else
  git -C "$VCPKG_ROOT" fetch --quiet origin || true
fi
[ -x "$VCPKG_ROOT/vcpkg" ] || "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics

say "4/7 Configure"
SRC="$WORK/source"
rm -rf "$SRC"; cp -R "$HERE/source" "$SRC"
BUILD="$WORK/build-$ARCH"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET="$TRIPLET" -DVCPKG_HOST_TRIPLET="$TRIPLET" -DVCPKG_BUILD_TYPE=release \
  -DVCPKG_INSTALL_OPTIONS="--clean-buildtrees-after-build" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBRARY=ON -DSPEED_UP_BUILD_UNITY=ON \
  -DOPTIONS_ENABLE_SCCACHE=OFF -DOPTIONS_ENABLE_IPO=OFF -DOTCLIENT_BUILD_TESTS=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  || die "configure failed"

say "5/7 Build"
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)" || die "build failed"
BIN="$(find "$SRC" "$BUILD" -path '*OTClient.app/Contents/MacOS/OTClient' -type f 2>/dev/null | head -1 || true)"
[ -n "$BIN" ] || BIN="$(find "$SRC" "$BUILD" -maxdepth 3 -name otclient -type f -perm +111 2>/dev/null | head -1 || true)"
[ -n "$BIN" ] || die "the built program was not found"
echo "Program: $BIN"

say "6/7 Game data and OurTibia.app"
DATA_SRC="$WORK/data"
rm -rf "$DATA_SRC"; mkdir -p "$DATA_SRC"
# game data: argument (local .tar.gz or .zip), or OURTIBIA_DATA_URL, or the Linux package
ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  URL="${OURTIBIA_DATA_URL:-$DATA_URL}"
  ARCHIVE="$WORK/client-data.${URL##*.}"
  curl -fL --progress-bar -o "$ARCHIVE" "$URL" || die "cannot download $URL"
fi
case "$ARCHIVE" in
  *.zip) unzip -q "$ARCHIVE" -d "$DATA_SRC" ;;
  *) tar -xzf "$ARCHIVE" -C "$DATA_SRC" ;;
esac
GAME="$(find "$DATA_SRC" -maxdepth 3 -name init.lua -type f 2>/dev/null | head -1 || true)"
[ -n "$GAME" ] || die "init.lua not found in the game data"
GAME="$(dirname "$GAME")"
# newest modules and client files (OURTIBIA_OVERLAY folder) over the downloaded data
if [ -n "${OURTIBIA_OVERLAY:-}" ] && [ -d "$OURTIBIA_OVERLAY" ]; then
  echo "Overlay: $OURTIBIA_OVERLAY"
  [ -d "$OURTIBIA_OVERLAY/modules" ] && rm -rf "$GAME/modules"
  cp -R "$OURTIBIA_OVERLAY/." "$GAME/"
fi

APP="$OUT/OurTibia.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/otclient-bin"
chmod +x "$APP/Contents/MacOS/otclient-bin"
# The client looks for init.lua in the current folder first, so the launcher starts it
# from Resources (game data inside the app). The program name must not start with
# "ourtibia": at start the client switches to the newest file with the same name
# (up to the first '-') in its folder and deletes the others.
cat > "$APP/Contents/MacOS/OurTibia" <<'EOF'
#!/bin/sh
cd "$(dirname "$0")/../Resources" || exit 1
exec ../MacOS/otclient-bin "$@"
EOF
chmod +x "$APP/Contents/MacOS/OurTibia"
for f in init.lua config.ini cacert.pem update-public-key.xml update-url.txt; do
  [ -f "$GAME/$f" ] && cp "$GAME/$f" "$APP/Contents/Resources/"
done
for d in mods modules data; do cp -R "$GAME/$d" "$APP/Contents/Resources/"; done
cp "$HERE/OurTibia.icns" "$APP/Contents/Resources/OurTibia.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OurTibia</string>
  <key>CFBundleDisplayName</key><string>OurTibia</string>
  <key>CFBundleIdentifier</key><string>com.ourtibia.client</string>
  <key>CFBundleExecutable</key><string>OurTibia</string>
  <key>CFBundleIconFile</key><string>OurTibia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d)</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

echo "Libraries outside macOS:"
otool -L "$APP/Contents/MacOS/otclient-bin" | tail -n +2 | grep -v -E '/System/Library/|/usr/lib/' || echo "  none (all built in)"
if otool -L "$APP/Contents/MacOS/otclient-bin" | tail -n +2 | grep -q -E '/opt/homebrew|/usr/local'; then
  die "the program uses Homebrew libraries - it would not start on other Macs"
fi

xattr -cr "$APP"
codesign --force --deep --sign - "$APP" || die "codesign failed"
codesign --verify --deep "$APP" && echo "Signature OK (ad-hoc)"

say "7/7 Start test (25 seconds)"
rm -f "$APP/Contents/Resources/myots1098.log"
"$APP/Contents/MacOS/OurTibia" >"$OUT/start-test.txt" 2>&1 &
PID=$!
sleep 25
if kill -0 "$PID" 2>/dev/null; then
  echo "The client is running."
  kill "$PID" 2>/dev/null || true; sleep 2; kill -9 "$PID" 2>/dev/null || true
  RUN_OK=1
else
  echo "The client CLOSED by itself - see $OUT/start-test.txt"
  RUN_OK=0
fi
GAMELOG="$APP/Contents/Resources/myots1098.log"
if [ -f "$GAMELOG" ]; then
  cp "$GAMELOG" "$OUT/client-log.txt"
  echo "Errors in the client log (audio/game_bot messages are normal):"
  grep -i -E 'error|fatal|unable' "$GAMELOG" | grep -v -i -E 'audio|game_bot|OurUpdater' || echo "  none"
  rm -f "$GAMELOG"
fi
codesign --force --deep --sign - "$APP" >/dev/null

ZIP="$OUT/OurTibia-macOS-$ARCH.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"
if [ "$RUN_OK" = 1 ]; then
  say "DONE. Now open out/OurTibia.app, log in and play a moment (walk, chat, open the Store)."
  echo "If it works, send back: $ZIP  (and out/build.log)"
else
  die "the client did not stay open - send out/build.log, out/start-test.txt and out/client-log.txt"
fi
