#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Notchturne.app"

rm -rf "$ROOT/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
    -target arm64-apple-macos14.0 \
    -framework AppKit -framework SwiftUI \
    -o "$APP/Contents/MacOS/Notchturne" \
    "$ROOT/Sources/"*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Тексты системных запросов доступа показывает macOS, а не приложение,
# поэтому они живут отдельно и следуют языку системы, а не настройке в панели.
for lang in en ru; do
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    cp "$ROOT/Resources/$lang.lproj/InfoPlist.strings" "$APP/Contents/Resources/$lang.lproj/"
done

# Подпись. Локальная (adhoc) даёт отпечаток, который меняется при каждой
# сборке — и macOS каждый раз заново спрашивает доступ к Музыке и Календарю.
# Если в связке ключей есть сертификат для подписи кода, берём его:
# отпечаток становится постоянным и разрешения переживают пересборку.
IDENTITY="${CODESIGN_IDENTITY:-Notchturne Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "подписано сертификатом: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "подписано локально (adhoc) — разрешения будут спрашиваться после каждой сборки"
fi

echo "готово: $APP"
