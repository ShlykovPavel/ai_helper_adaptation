#!/usr/bin/env bash
set -euo pipefail

# Ensure consistent UTF-8 handling for filenames and text
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

ORIG_PWD="$(pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION=""
OUTPUT_DIR=""
APP_PATH=""
SKIP_BUILD=false

usage() {
    cat << EOF
Usage: $(basename "$0") [version] [options]

Builds and packages Coucou into universal DMG and ZIP distribution archives
with ad-hoc codesigning and Gatekeeper unlock helpers.

Options:
  --version <ver>      Version string (auto-detected from Info.plist / project.yml if omitted)
  --output-dir <dir>   Directory to place generated archives (default: dist/)
  --app-path <path>    Use pre-built Coucou.app instead of building from source
  --skip-build         Use existing Coucou.app from DerivedData if available
  -h, --help           Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            if [ $# -lt 2 ]; then
                echo "error: --version requires an argument" >&2
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION="${1#*=}"
            shift 1
            ;;
        --output-dir)
            if [ $# -lt 2 ]; then
                echo "error: --output-dir requires an argument" >&2
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
            shift 1
            ;;
        --app-path)
            if [ $# -lt 2 ]; then
                echo "error: --app-path requires an argument" >&2
                exit 1
            fi
            APP_PATH="$2"
            SKIP_BUILD=true
            shift 2
            ;;
        --app-path=*)
            APP_PATH="${1#*=}"
            SKIP_BUILD=true
            shift 1
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo "error: unexpected argument '$1'" >&2
                usage >&2
                exit 1
            fi
            shift 1
            ;;
    esac
done

# ── 1. Determine Version ──────────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
    if [ -f "$REPO_ROOT/NotchBuddy/Resources/Info.plist" ]; then
        VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$REPO_ROOT/NotchBuddy/Resources/Info.plist" 2>/dev/null || true)"
    fi
    if [ -z "$VERSION" ] && [ -f "$REPO_ROOT/NotchBuddy/project.yml" ]; then
        VERSION="$(grep -m1 'CFBundleShortVersionString:' "$REPO_ROOT/NotchBuddy/project.yml" | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    fi
    if [ -z "$VERSION" ]; then
        VERSION="0.4.0"
    fi
fi

echo "Packaging Coucou version: $VERSION"

# ── 2. Determine Output Directory ─────────────────────────────────────────────
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$REPO_ROOT/dist"
else
    if [[ "$OUTPUT_DIR" != /* ]]; then
        OUTPUT_DIR="$ORIG_PWD/$OUTPUT_DIR"
    fi
fi
mkdir -p "$OUTPUT_DIR"

# ── 3. Prepare Staging Directory ──────────────────────────────────────────────
STAGING_DIR="$(mktemp -d -t coucou-package.XXXXXX)"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT INT TERM

BUILD_DIR="$STAGING_DIR/build"
PAYLOAD_DIR="$STAGING_DIR/payload"
mkdir -p "$BUILD_DIR" "$PAYLOAD_DIR"

# ── 4. Obtain or Build Coucou.app ─────────────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
    echo "==> Building Universal Release binary via scripts/build-release.sh..."
    "$REPO_ROOT/scripts/build-release.sh" --build-dir "$BUILD_DIR"
    SOURCE_APP="$BUILD_DIR/Coucou.app"
else
    if [ -n "$APP_PATH" ]; then
        SOURCE_APP="$APP_PATH"
    else
        SOURCE_APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path '*/Build/Products/Release/Coucou.app' 2>/dev/null | head -n 1 || true)"
    fi
fi

if [ -z "$SOURCE_APP" ] || [ ! -d "$SOURCE_APP" ]; then
    echo "error: Coucou.app not found at '${SOURCE_APP:-<empty>}'" >&2
    exit 1
fi

echo "==> Copying Coucou.app into staging payload..."
cp -R "$SOURCE_APP" "$PAYLOAD_DIR/Coucou.app"
TARGET_APP="$PAYLOAD_DIR/Coucou.app"

# ── 5. Apply Ad-hoc Codesign ──────────────────────────────────────────────────
echo "==> Applying ad-hoc codesign to Coucou.app..."
codesign --force --deep -s - "$TARGET_APP"

# ── 6. Verify Universal Architecture & Signature ──────────────────────────────
echo "==> Verifying binary architecture and code signature..."
TARGET_BINARY="$TARGET_APP/Contents/MacOS/Coucou"
if [ ! -f "$TARGET_BINARY" ]; then
    echo "error: Mach-O binary not found at '$TARGET_BINARY'" >&2
    exit 1
fi

LIPO_OUT="$(lipo -info "$TARGET_BINARY")"
echo "    Binary architectures: $LIPO_OUT"
if ! echo "$LIPO_OUT" | grep -q "arm64" || ! echo "$LIPO_OUT" | grep -q "x86_64"; then
    echo "error: binary at '$TARGET_BINARY' is not Universal (must contain both arm64 and x86_64)" >&2
    exit 1
fi

codesign -v --deep "$TARGET_APP"
echo "    Code signature verified: valid ad-hoc signature."

# ── 7. Generate Instructions (ИНСТРУКЦИЯ.txt) ─────────────────────────────────
echo "==> Creating ИНСТРУКЦИЯ.txt..."
cat << 'EOF' > "$PAYLOAD_DIR/ИНСТРУКЦИЯ.txt"
================================================================================
                    ИНСТРУКЦИЯ ПО УСТАНОВКЕ И ЗАПУСКУ COUCOU
================================================================================

1. УСТАНОВКА
--------------------------------------------------------------------------------
1. Перетащите файл Coucou.app в системную папку «Программы» (/Applications).
   ВАЖНО: Приложение должно запускаться именно из папки /Applications.


2. ПЕРВЫЙ ЗАПУСК И GATEKEEPER («Приложение повреждено» / «Не удается проверить»)
--------------------------------------------------------------------------------
Так как данная сборка подготовлена без платного сертификата Apple Developer ID
(ad-hoc подпись), система защиты macOS Gatekeeper при первом запуске может
заблокировать приложение и вывести сообщение:
  «Приложение "Coucou" повреждено и его невозможно открыть»
или:
  «macOS не удается проверить разработчика "Coucou"»

Чтобы запустить приложение, выполните ОДНО из следующих действий:

СПОСОБ 1 (Самый простой — скрипт разблокировки):
  Дважды нажмите на файл «Разблокировать_Coucou.command» рядом с приложением.
  Откроется окно Терминала, снимет атрибут карантина с /Applications/Coucou.app
  и сообщит об успешном завершении. После этого приложение сразу можно открывать.

СПОСОБ 2 (Через Настройки macOS):
  1. Попробуйте открыть Coucou.app (появится предупреждение от macOS).
  2. Откройте «Системные настройки» → «Конфиденциальность и безопасность».
  3. Прокрутите вниз до раздела «Безопасность».
  4. Нажмите «Подтвердить вход» («Открыть в любом случае») напротив Coucou.

СПОСОБ 3 (Вручную в Терминале):
  Откройте программу «Терминал» и выполните команду:
  xattr -cr /Applications/Coucou.app


3. РАЗРЕШЕНИЯ СИСТЕМЫ (Универсальный доступ / Accessibility)
--------------------------------------------------------------------------------
Для отображения интерфейса вокруг выреза (Notch) и корректного отслеживания
положения окон приложению требуется разрешение «Универсальный доступ»:

1. Откройте «Системные настройки» (System Settings).
2. Перейдите в раздел «Конфиденциальность и безопасность» (Privacy & Security).
3. Выберите пункт «Универсальный доступ» (Accessibility).
4. Найдите Coucou в списке и включите переключатель.
   (Если Coucou нет в списке, нажмите «+» и выберите /Applications/Coucou.app).
5. При запросе разрешения на «Запись экрана» (Screen Recording) подтвердите его,
   если планируете использовать определение границ выреза на экране.


4. СОВМЕСТИМОСТЬ
--------------------------------------------------------------------------------
- Поддерживается macOS 15.0 (Sequoia) и новее.
- Универсальная сборка (Universal Binary): одинаково быстро работает как на
  компьютерах с чипами Apple Silicon (M1/M2/M3/M4), так и на Intel.

================================================================================
EOF

# ── 8. Generate Unlock Script (Разблокировать_Coucou.command) ─────────────────
echo "==> Creating Разблокировать_Coucou.command..."
cat << 'EOF' > "$PAYLOAD_DIR/Разблокировать_Coucou.command"
#!/bin/bash
# Скрипт снятия карантина macOS Gatekeeper с Coucou.app

echo "=========================================================="
echo "    Coucou: Снятие карантина macOS Gatekeeper"
echo "=========================================================="
echo

APP_PATH="/Applications/Coucou.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ОШИБКА: $APP_PATH не найден!"
    echo "Сначала перетащите Coucou.app в папку «Программы» (/Applications)."
    echo
else
    echo "Снятие атрибута карантина (com.apple.quarantine) с $APP_PATH..."
    if xattr -cr "$APP_PATH" 2>/dev/null; then
        echo
        echo "✓ Успешно! Карантин снят."
        echo "Теперь вы можете запустить Coucou из папки «Программы»."
        echo
    else
        echo
        echo "Требуются повышенные права. Введите пароль администратора:"
        if sudo xattr -cr "$APP_PATH"; then
            echo
            echo "✓ Успешно! Карантин снят."
            echo "Теперь вы можете запустить Coucou из папки «Программы»."
            echo
        else
            echo "Не удалось снять карантин. Проверьте права доступа к $APP_PATH."
            echo
        fi
    fi
fi

echo "Нажмите любую клавишу для закрытия окна..."
read -n 1 -s -r 2>/dev/null || read -r dummy 2>/dev/null || true
exit 0
EOF
chmod +x "$PAYLOAD_DIR/Разблокировать_Coucou.command"

# ── 9. Build DMG and ZIP Archives ─────────────────────────────────────────────
DMG_NAME="Coucou-${VERSION}-macOS-Universal.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
ZIP_NAME="Coucou-${VERSION}-macOS-Universal.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "==> Building DMG: $DMG_PATH..."
hdiutil create \
    -volname "Coucou" \
    -srcfolder "$PAYLOAD_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Building ZIP: $ZIP_PATH..."
rm -f "$ZIP_PATH"
ditto -c -k "$PAYLOAD_DIR" "$ZIP_PATH"

# ── 10. Verify Output Artifacts ───────────────────────────────────────────────
if [ ! -f "$DMG_PATH" ]; then
    echo "error: DMG file was not created at '$DMG_PATH'" >&2
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "error: ZIP file was not created at '$ZIP_PATH'" >&2
    exit 1
fi

DMG_SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
ZIP_SIZE="$(du -h "$ZIP_PATH" | awk '{print $1}')"

echo
echo "=========================================================="
echo "    Coucou Universal Package Created Successfully!"
echo "=========================================================="
echo "Version: $VERSION"
echo "Outputs:"
echo "  • DMG: $DMG_PATH ($DMG_SIZE)"
echo "  • ZIP: $ZIP_PATH ($ZIP_SIZE)"
echo "Contents:"
echo "  • Coucou.app (Universal: arm64 + x86_64, ad-hoc signed)"
echo "  • ИНСТРУКЦИЯ.txt"
echo "  • Разблокировать_Coucou.command (chmod +x)"
echo "=========================================================="
