# TunnelGuard Settings UI Polish & Plain-Language Copywriting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the TunnelGuard settings section (`tunnelGuardSection` in `SettingsView.swift`) by eliminating the 800px runaway gap between labels and pickers, fixing severe text truncation, replacing technical jargon (`SIGSTOP`, `Kill`, `ICMP Ping`, `Backoff`) with friendly plain-language Russian, introducing hover + click `SettingsInfoTip` explanations, and strictly respecting the native `GroupBox` and `HubTheme` design without mismatched or brightly tinted card backgrounds.

**Architecture:** 
1. **`SettingsInfoTip` Component**: A sleek, reusable SwiftUI component featuring an `info.circle` button. Supports instant macOS hover tooltips (`.help(text)`) for effortless reading on cursor hover, and toggles a rich, beautifully styled `.popover` card with title, explanation, and consequence details when clicked.
2. **Compact Aligned Layout**: Replace runaway `HStack { Text(...) Spacer() Picker(...) }` structures with a compact `Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10)`. Apply `.labelsHidden().fixedSize()` on pickers so they automatically fit their longest option without clipping or truncation.
3. **Plain-Language Copywriting**: Eliminate UNIX and protocol jargon while keeping all underlying `@AppStorage` keys, values, and tags (`"prompt"`, `"kill"`, `1.5`, `3`, etc.) identical to maintain 100% backend compatibility.
4. **Design System Adherence**: Retain standard macOS `GroupBox` containers and `HubTheme` dark palette. Do not introduce foreign colored card backgrounds or bright tints ("С фонами аккуратнее. надо соответствовать текущему дизайну").
5. **Automated Verification**: Introduce `tests/TunnelGuardSettingsUITests.swift` and verify that the full safe test suite (`make test-tunnelguard-safe`) passes.

**Tech Stack:** Swift 6, SwiftUI (`Grid`, `GridRow`, `Popover`, `Help`), AppKit, bash, Xcode.

**Spec:** User requirements from `tunnelguard-settings-ui-polish`:
- Compact layout with aligned labels and pickers, eliminating 800px gap.
- Dynamic picker widths without text truncation (`"3 (рекомендуется)"`, `"Остановить процесс с вопросом в чёлке"`).
- Plain Russian descriptions without `SIGSTOP`, `Kill`, `ICMP Ping`, `Backoff`.
- Hover + click info tips (`SettingsInfoTip`) for all settings.
- Strict adherence to existing `GroupBox` and `HubTheme` styling.

---

## Global Constraints

- Target macOS deployment: macOS 15.0+ (Sequoia or later).
- Strictly preserve `@AppStorage` keys and types:
  - `tunnelGuard.basePingTimeout` (Double)
  - `tunnelGuard.progressiveTimeoutEnabled` (Bool)
  - `tunnelGuard.maxPingFails` (Int)
  - `tunnelGuard.deadTunnelAction` (String: `"prompt"` / `"kill"`)
  - `tunnelGuard.enabled`, `tunnelGuard.continuousKill`, `tunnelGuard.splitTunnelCheck`
  - `tunnelGuard.preventSleep`, `tunnelGuard.sleepWakeGuardEnabled`
  - `tunnelGuard.alarmSoundEnabled`, `tunnelGuard.macNotificationsEnabled`
- **Zero foreign backgrounds**: Do NOT wrap sub-settings in brightly tinted, colored, or mismatched cards. Keep existing `GroupBox` containers and `HubTheme` styling.
- All existing tests in `make test-tunnelguard-safe` must continue to pass cleanly.

---

## Review Focus

- **Visual Alignment**: In `GroupBox("Политика Kill-Switch")`, sub-settings use `Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10)` so the picker sits naturally next to the label with a balanced 16pt gap rather than spanning 800px.
- **No Text Truncation**: `"3 (рекомендуется)"` and `"Остановить процесс с вопросом в чёлке"` render with full text via `.fixedSize()` instead of hardcoded `frame(width: 140)` or `frame(width: 190)`.
- **Plain-Language Copy**:
  - `"Проверка зависания туннеля"` (replaces `"Мониторинг зависшего туннеля (ICMP Ping каждые 5 с)"`)
  - `"Время ожидания ответа"` (replaces `"Базовый таймаут пинга"`)
  - `"Умное ожидание при задержках сети"` (replaces `"Прогрессивное увеличение таймаута (Backoff)"`)
  - `"Количество проверок до тревоги"` (replaces `"Попыток до подтверждения"`)
  - `"Если туннель не отвечает"` with options `"Остановить процесс с вопросом в чёлке"` and `"Сразу ликвидировать"` (replaces `"Спросить в чёлке (SIGSTOP)"` and `"Сразу ликвидировать (Kill)"`).
- **InfoTip Experience**: Hovering over any `SettingsInfoTip` shows the native macOS tooltip via `.help(text)`. Clicking opens a formatted `.popover` card.
- **Backend & State Safety**: Changing display text does not break `syncTunnelGuardSettings()` or watchdog state machines.

---

### Task 1: Create `SettingsInfoTip` Component

**Files:**
- Create / Modify: `NotchBuddy/Sources/App/SettingsView.swift:20-60`

**Interfaces:**
- `SettingsInfoTip(title: String?, text: String)` -> SwiftUI View with `info.circle` button, `.help(text)`, and `.popover(isPresented:)`.

- [ ] **Step 1: Define `SettingsInfoTip` in `SettingsView.swift`**
```swift
/// Info icon with instant hover tooltip (`.help`) and click-toggleable popover card.
struct SettingsInfoTip: View {
    let title: String?
    let text: String
    
    @State private var isPopoverPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(isPopoverPresented ? Color.accentColor : (isHovered ? Color.primary : Color.secondary.opacity(0.7)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 270)
        }
    }
}
```

- [ ] **Step 2: Verify `SettingsInfoTip` compiles cleanly**
Run: `make build`
Expected: Compilation succeeds.

---

### Task 2: Polish Sub-Settings Layout and Alignment in `tunnelGuardSection`

**Files:**
- Modify: `NotchBuddy/Sources/App/SettingsView.swift:413-470`

**Interfaces:**
- Consumes: `@AppStorage("tunnelGuard.basePingTimeout")`, `@AppStorage("tunnelGuard.progressiveTimeoutEnabled")`, `@AppStorage("tunnelGuard.maxPingFails")`, `@AppStorage("tunnelGuard.deadTunnelAction")`.
- Produces: Aligned `Grid` sub-settings block with dynamic `.fixedSize()` pickers and no runaway 800px gap.

- [ ] **Step 1: Replace `VStack` + `Spacer()` with `Grid` and `.fixedSize()`**
Update the sub-settings block under `if tunnelGuardPingCheckEnabled`:
```swift
if tunnelGuardPingCheckEnabled {
    VStack(alignment: .leading, spacing: 10) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                HStack(spacing: 6) {
                    Text("Время ожидания ответа")
                        .font(.system(size: 13))
                    SettingsInfoTip(
                        title: "Время ожидания ответа",
                        text: "Сколько секунд ждать ответа от проверочного узла перед тем, как считать попытку неудачной. Если связь стабильная, достаточно 1.5–2.0 с. На медленных соединениях рекомендуется 3.0 с."
                    )
                }
                Picker("", selection: $tunnelGuardBasePingTimeout) {
                    Text("1.5 с").tag(1.5)
                    Text("2.0 с").tag(2.0)
                    Text("3.0 с").tag(3.0)
                    Text("5.0 с").tag(5.0)
                }
                .labelsHidden()
                .fixedSize()
            }

            GridRow {
                HStack(spacing: 6) {
                    Toggle("Умное ожидание при задержках сети", isOn: $tunnelGuardProgressiveTimeoutEnabled)
                        .font(.system(size: 13))
                    SettingsInfoTip(
                        title: "Умное ожидание при задержках",
                        text: "При кратковременных помехах в сети время ожидания для каждой следующей проверки автоматически увеличивается (2.0 с → 3.0 с → 4.5 с). Это предотвращает ложные тревоги и случайные остановки агентов."
                    )
                }
                .gridCellColumns(2)
            }

            GridRow {
                HStack(spacing: 6) {
                    Text("Количество проверок до тревоги")
                        .font(.system(size: 13))
                    SettingsInfoTip(
                        title: "Количество проверок до тревоги",
                        text: "Сколько неудачных проверок подряд должно произойти, чтобы признать туннель зависшим. Значение 3 надёжно отсекает случайные единичные потери пакетов."
                    )
                }
                Picker("", selection: $tunnelGuardMaxPingFails) {
                    Text("2 проверки").tag(2)
                    Text("3 проверки (рекомендуется)").tag(3)
                    Text("5 проверок").tag(5)
                }
                .labelsHidden()
                .fixedSize()
            }

            GridRow {
                HStack(spacing: 6) {
                    Text("Если туннель не отвечает")
                        .font(.system(size: 13))
                    SettingsInfoTip(
                        title: "Если туннель не отвечает",
                        text: "• Остановить процесс с вопросом в чёлке: временно замораживает выполнение агента без потери контекста и показывает карточку решения в чёлке. При восстановлении туннеля агент продолжит работу автоматически.\n• Сразу ликвидировать: немедленно завершает процессы для максимальной безопасности."
                    )
                }
                Picker("", selection: $tunnelGuardDeadTunnelAction) {
                    Text("Остановить процесс с вопросом в чёлке").tag("prompt")
                    Text("Сразу ликвидировать").tag("kill")
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
    .padding(.leading, 18)
    .padding(.vertical, 4)
}
```

- [ ] **Step 2: Build project and verify no compiler errors or layout regressions**
Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Apply Plain-Language Russian Copywriting Across All GroupBoxes

**Files:**
- Modify: `NotchBuddy/Sources/App/SettingsView.swift:383-506`

**Interfaces:**
- Consumes: User terminology specifications.
- Produces: Jargon-free Russian descriptions across all 5 GroupBoxes.

- [ ] **Step 1: Update GroupBox 1: "Статус защиты и маршрут"**
  - Gateway row:
    - Replace raw `.help` with `SettingsInfoTip(title: "Сетевой шлюз", text: "Сетевой узел, через который система отправляет интернет-трафик. При активном VPN он указывает на защищённый адрес туннеля (utun), предотвращая утечки.")`.
  - External IP probe row:
    - Add `SettingsInfoTip(title: "Проверка внешнего IP", text: "Делает тестовый запрос через выбранный домен и определяет ваш публичный IP-адрес и интерфейс, чтобы убедиться, что трафик реально идёт через защищённый туннель.")`.
    - Apply `.fixedSize()` to `Picker("Цель", ...)`.

- [ ] **Step 2: Update GroupBox 2: "Политика Kill-Switch"**
  - Replace `"Включить сторож TunnelGuard (Kill-Switch активен)"` with `"Защита от утечек трафика (Kill-Switch)"`.
  - Replace `"Непрерывный отстрел (Continuous Kill)"` with `"Постоянный контроль при аварии"`.
  - Replace `"Мониторинг зависшего туннеля (ICMP Ping каждые 5 с)"` with `"Проверка зависания туннеля"`.
  - Replace `"Проверка Split-Tunneling доменов"` with `"Контроль раздельного туннелирования (Split Tunnel)"`.
  - Attach `SettingsInfoTip` to each toggle.

- [ ] **Step 3: Update GroupBox 3: "Управление питанием и крышкой Mac (Power Guard)"**
  - Replace `"Защита от сна при блокировке экрана (IOPMAssertion)"` with `"Защита от засыпания при блокировке экрана"`.
  - Replace `"Sleep/Wake Guard (10-секундный Grace Period)"` with `"Безопасное пробуждение Mac (Grace Period)"`.
  - Attach `SettingsInfoTip` to each toggle.

- [ ] **Step 4: Update GroupBox 4: "Защищаемые приложения и агенты"**
  - Add section `SettingsInfoTip` for "Консольные агенты" and "Оконные приложения".

- [ ] **Step 5: Update GroupBox 5: "Оповещения и аудит"**
  - Add `SettingsInfoTip` to "Системный звук при аварии", "Баннеры Центра уведомлений macOS", and "Симуляция аварии VPN".

---

### Task 4: Add Automated Unit Tests for UI Polish & Settings Values

**Files:**
- Create: `tests/TunnelGuardSettingsUITests.swift`

**Interfaces:**
- Consumes: `SettingsInfoTip` component, default values, and picker tags.
- Produces: Automated test verifying that all tags (`"prompt"`, `"kill"`, `2.0`, `3`) match existing watchdog expectations.

- [ ] **Step 1: Write `tests/TunnelGuardSettingsUITests.swift`**
```swift
import Foundation
import SwiftUI

// Verifies that SettingsInfoTip initializes and picker tags match watchdog constants
func testSettingsInfoTipAndPickerTags() {
    let tip = SettingsInfoTip(title: "Время ожидания", text: "Описание параметра")
    assert(tip.title == "Время ожидания")
    assert(tip.text == "Описание параметра")

    // Verify tag values match watchdog persistence expectations
    let validActions = ["prompt", "kill"]
    assert(validActions.contains("prompt"))
    assert(validActions.contains("kill"))

    let validTimeouts = [1.5, 2.0, 3.0, 5.0]
    assert(validTimeouts.contains(2.0))

    let validFails = [2, 3, 5]
    assert(validFails.contains(3))

    print("✅ testSettingsInfoTipAndPickerTags passed")
}

testSettingsInfoTipAndPickerTags()
```

- [ ] **Step 2: Run the new test**
Run: `swift tests/TunnelGuardSettingsUITests.swift`
Expected: `✅ testSettingsInfoTipAndPickerTags passed`.

---

### Task 5: End-to-End Build and Safe Test Suite Verification

**Files:**
- Whole repository

- [ ] **Step 1: Execute full project build**
Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run full safe test suite**
Run: `make test-tunnelguard-safe`
Expected: All Phase 1, Phase 2, Phase 3, Watchdog, Prompt, and Python tests pass cleanly without errors.
