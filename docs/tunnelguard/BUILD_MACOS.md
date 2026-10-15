# Сборка и запуск Coucou (NotchBuddy) на macOS

В данном руководстве описан процесс подготовки окружения, сборки и запуска приложения **Coucou (NotchBuddy)** на macOS (включая ветку с интеграцией **TunnelGuard**).

---

## 1. Системные требования

- **Операционная система**: macOS 15.0 (Sequoia) или новее.
- **Инструменты разработки**:
  - Xcode 16.0+ (доступен в Mac App Store) или актуальные Xcode Command Line Tools.
  - Swift 6.0 toolchain (поставляется вместе с Xcode 16).
  - Утилита [XcodeGen](https://github.com/yonaskolb/XcodeGen) для генерации `.xcodeproj`.
  - Python 3 (`/usr/bin/python3` или Homebrew Python).

---

## 2. Установка зависимостей

Установите менеджер пакетов [Homebrew](https://brew.sh) (если еще не установлен) и необходимые утилиты:

```bash
# Установка Command Line Tools (если не установлены)
xcode-select --install

# Установка генератора Xcode-проектов
brew install xcodegen
```

Проверьте доступность инструментов в терминале:
```bash
xcodegen --version
xcodebuild -version
swift --version
```

---

## 3. Особенности подписи кода в нашем форке

В оригинальном репозитории Coucou настроена обязательная подпись с Apple Developer Team ID (`256AUJ9555`) и сертификатами App Store. Сборка такого проекта на машине без платного аккаунта Apple Developer завершается ошибкой `Signing for 'NotchBuddy' requires a development team`.

В нашем форке файл [`NotchBuddy/project.yml`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/project.yml) адаптирован для **беспрепятственной локальной сборки**:
- `CODE_SIGNING_REQUIRED: NO`
- `CODE_SIGNING_ALLOWED: NO` (для Debug и Release)
- `CODE_SIGN_IDENTITY: ""`
- Удалены специфичные схемы AppStore.

Это позволяет собрать и запустить приложение на любом Mac без каких-либо сертификатов.

---

## 4. Генерация Xcode-проекта (XcodeGen)

> **ВАЖНО!** Не редактируйте файлы внутри `NotchBuddy.xcodeproj` вручную. Все настройки хранятся в `NotchBuddy/project.yml`.

Перед первой сборкой (или после любых изменений в структуре файлов и `project.yml`) сгенерируйте `.xcodeproj`:

```bash
cd NotchBuddy
xcodegen
cd ..
```

Вывод команды должен подтвердить создание проекта:
```text
Loaded project:
  Name: NotchBuddy
  Targets:
    NotchBuddy: application
    CoucouPhone: application
Saved project to NotchBuddy.xcodeproj
```

---

## 5. Сборка из терминала (CLI)

### Вариант A. Стандартная Debug-сборка (в DerivedData)
```bash
cd NotchBuddy
xcodebuild -scheme NotchBuddy -configuration Debug build
cd ..
```
После успешного завершения (`** BUILD SUCCEEDED **`) бинарный бандл будет расположен по системному пути DerivedData:
`~/Library/Developer/Xcode/DerivedData/NotchBuddy-*/Build/Products/Debug/Coucou.app`

---

### Вариант B. Сборка в локальную директорию (Рекомендуется)
Чтобы приложение собралось прямо в локальную папку проекта, передайте параметр `-derivedDataPath`:

```bash
cd NotchBuddy
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath ./build build
cd ..
```

Готовое приложение появится по пути:
```text
NotchBuddy/build/Build/Products/Debug/Coucou.app
```

Для сборки оптимизированного Release-билда:
```bash
cd NotchBuddy
xcodebuild -scheme NotchBuddy -configuration Release -derivedDataPath ./build build
cd ..
```

---

### Вариант C. Быстрая сборка через Makefile
В корне репозитория доступны готовые команды make:
```bash
# Сборка Debug-конфигурации
make build

# Сборка Release-конфигурации
make build-release
# или: ./scripts/build-release.sh

# Сборка универсального дистрибутива (DMG и ZIP) для коллег
make package
# или: make dist
```

---

## 6. Сборка и запуск через Xcode (GUI)

1. Откройте сгенерированный проект в Xcode:
   ```bash
   open NotchBuddy/NotchBuddy.xcodeproj
   ```
2. В верхнем селекторе схем убедитесь, что выбрана схема **NotchBuddy** и целевое устройство **My Mac**:
   ```text
   [ NotchBuddy > My Mac ]
   ```
3. *(При необходимости)* Перейдите в настройки таргshared: вкладка **Signing & Capabilities** → в поле Signing выберите **Sign to Run Locally** (локальная Ad-hoc подпись).
4. Нажмите сочетание клавиш **Cmd + R** или кнопку **Run (▶)** для сборки и запуска приложения.

---

## 7. Запуск приложения на Mac

### Запуск из терминала
```bash
# Запуск локально собранного приложения
open NotchBuddy/build/Build/Products/Debug/Coucou.app
```

Либо скопируйте приложение в системную папку программ:
```bash
cp -R NotchBuddy/build/Build/Products/Debug/Coucou.app /Applications/
open -a Coucou
```

### Снятие карантина Gatekeeper
Если приложение запускается на другом Mac или переносилось через сеть/архив, macOS может заблокировать его из-за отсутствия нотаризации. Снимите флаг карантина:
```bash
xattr -cr /Applications/Coucou.app
# или для локальной папки:
xattr -cr NotchBuddy/build/Build/Products/Debug/Coucou.app
```

---

## 8. Необходимые системные разрешения macOS

Для полноценной работы чёлки, горячих клавиш и TunnelGuard Watchdog приложению требуются следующие системные права:

1. **Универсальный доступ (Accessibility)**:
   - Путь: *Системные настройки → Конфиденциальность и безопасность → Универсальный доступ*.
   - Включите тумблер для **Coucou**.
   - Требуется для отслеживания глобальных хоткеев и позиционирования над чёлкой.
2. **Запись экрана (Screen Recording)** *(опционально)*:
   - Требуется только если вы используете функцию "Drag Mochi onto any window" для передачи контекста открытого окна в Claude.
3. **Уведомления (Notifications)**:
   - Разрешите показ баннеров при первом запросе приложения для отображения статусов агентов.

---

## 9. Проверка запуска и работы

1. После старта приложения в верхней части экрана (в чёлке MacBook или по центру верхней кромки на внешнем мониторе) появится персонаж **Mochi**.
2. В строке меню macOS или при наведении на чёлку откроется интерфейс NotchBuddy.
3. В логах TunnelGuard начнётся фиксация активности сетевых интерфейсов:
   ```bash
   cat ~/Library/Logs/TunnelGuard/watchdog.log
   ```
4. Для остановки приложения нажмите правой кнопкой мыши по персонажу или иконке в строке состояния → **Quit**, либо в терминале:
   ```bash
   killall Coucou
   ```

---

## 10. Подготовка пакета для коллег (Distribution Packaging)

Для передачи готового приложения коллегам или друзьям без необходимости собирать проект из исходного кода используется цель `make package`.

### Сборка дистрибутива одной командой
```bash
make package
# либо алиас:
make dist
# либо напрямую скриптом с дополнительными опциями:
./scripts/package.sh [--version 0.4.0] [--output-dir dist]
```

### Что происходит при сборке
Скрипт `scripts/package.sh`:
1. Собирает универсальный бинарник Release (`arm64` + `x86_64`) через `./scripts/build-release.sh`.
2. Подписывает бандл локальной ad-hoc подписью (`codesign --force --deep -s -`), не требующей учетной записи разработчика Apple.
3. Проверяет архитектуру через `lipo` и валидность подписи.
4. Добавляет русскую инструкцию `ИНСТРУКЦИЯ.txt` и хелпер `Разблокировать_Coucou.command`.
5. Упаковывает всё в два готовых формата в директории `dist/`:
   - `Coucou-<version>-macOS-Universal.dmg` (образ диска с компрессией UDZO)
   - `Coucou-<version>-macOS-Universal.zip` (универсальный архив)

### Содержимое дистрибутива
Внутри каждого архива/образа находятся:
- **`Coucou.app`** — готовое универсальное приложение macOS (работает на Apple Silicon M1/M2/M3/M4 и на процессорах Intel).
- **`ИНСТРУКЦИЯ.txt`** — подробное текстовое руководство на русском языке с описанием шагов установки, предоставления разрешений и обхода предупреждений системы безопасности.
- **`Разблокировать_Coucou.command`** — исполняемый скрипт для снятия карантина macOS Gatekeeper («Приложение повреждено» или «Не удается проверить разработчика»). Запускается двойным кликом мыши в Finder и автоматически выполняет команду `xattr -cr /Applications/Coucou.app`.

### Инструкция для получателя пакета
При передаче архива или DMG коллеге достаточно передать следующий порядок действий:
1. Открыть `Coucou-...-Universal.dmg` или распаковать `.zip`.
2. Перетащить **`Coucou.app`** в системную папку **«Программы»** (`/Applications`).
3. При первом запуске macOS Gatekeeper может заблокировать открытие неподписанного Apple Developer сертификатом приложения. Для разблокировки:
   - **Самый быстрый способ**: дважды кликнуть по **`Разблокировать_Coucou.command`** рядом с приложением (откроется окно Терминала, снимет карантин с `/Applications/Coucou.app` и завершится).
   - **Альтернативный способ (через GUI)**: открыть *«Системные настройки» → «Конфиденциальность и безопасность»*, прокрутить до раздела *«Безопасность»* и нажать *«Подтвердить вход»* («Открыть в любом случае»).
   - **Вручную в консоли**: выполнить `xattr -cr /Applications/Coucou.app`.
4. В *«Системных настройках» → «Конфиденциальность и безопасность» → «Универсальный доступ» (Accessibility)* включить тумблер для **Coucou** (необходимо для позиционирования над чёлкой экрана).

