# Архитектурный план внедрения оставшихся механизмов Gestapo в Coucou (NotchBuddy)

Настоящий документ фиксирует утверждённый план полного переноса функционала из кодовой базы **Gestapo** (`/Users/pavel/start_tool`) в форк **Coucou** (`/Users/pavel/ai_helper_adaptation`).

## Текущий статус

По состоянию на 13 октября 2026 года завершены **Фазы 1, 2 и 3**. Сетевое ядро, Power Guard, непрерывный kill-switch, GUI Hunter, системные уведомления и UI щитка Gestapo реализованы и проходят безопасные автоматические проверки. Следующий этап — **Фаза 4: настройки Gestapo Guard**; полноценной вкладки настроек пока нет.

Последняя проверка:

- `make test-gestapo-safe` — safe-проверки Фаз 1, 3 и Python gate прошли;
- `./scripts/test-gestapo-phase2-safe.sh` — 4/4 проверки прошли;
- `make build` — `BUILD SUCCEEDED` без ошибок компиляции.
- Фаза 3: кнопка сброса тревоги блокируется до восстановления VPN; экран щитка показывает интерфейс, шлюз и ping; ручная проверка IP показывает маршрут до цели, выбранный IP-сервис и внешний IP.

---

## 1. Анализ механизмов из исходного Gestapo (`/Users/pavel/start_tool`)

### 1.1. Защита от засыпания системы (`IOPMAssertion`)
- **Исходники:** `src/GestapoBar.swift` (строки 450–478), `src/gestapo_core.py` (строки 344–398).
- **Проблема:** При блокировке экрана Mac (`Cmd+Ctrl+Q` или таймаут дисплея) macOS переводит систему в режим глубокого сна (`Idle System Sleep`), разрывая сокеты CLI-агентов (Claude Code, agy, codex) и зависая сетевой туннель.
- **Решение:**
  - Использование C-API IOKit: `IOPMAssertionCreateWithName(...)`.
  - Тип: `kIOPMAssertionTypePreventUserIdleSystemSleep as CFString` (дисплей гаснет и блокируется, но **CPU и сеть продолжают работать**).
  - Уровень: `kIOPMAssertionLevelOn` (255).
  - Снятие: `IOPMAssertionRelease` при завершении работы или остановке сессий агентов.

### 1.2. Sleep / Wake Guard (Крышка MacBook и 10-секундный Grace Period)
- **Исходники:** `src/GestapoBar.swift` (строки 490–499, 649–661, 797–818).
- **Проблема:** При закрытии крышки ноутбука macOS сбрасывает сетевой стек, а при открытии Wi-Fi поднимается за 300 мс, тогда как VPN-клиенту (WireGuard/OpenVPN/Tailscale) требуется 2–5 секунд для восстановления туннеля. Без защиты сторож моментально убьёт агентов при открытии крышки!
- **Решение:**
  - Подписка через `NSWorkspace.shared.notificationCenter` на:
    - `NSWorkspace.willSleepNotification` -> заморозка проверок и пингов.
    - `NSWorkspace.didWakeNotification` -> взведение 10-секундного окна `wakeGracePeriodUntil = Date().timeIntervalSince1970 + 10.0`.
  - Во время этого окна сетевые сбои и пропуски пингов игнорируются, исключая ложные тревоги.

### 1.3. Детект зависшего туннеля (Dead Tunnel Detection / PingWorker)
- **Исходники:** `src/gestapo_core.py` (строки 1015–1051), `src/GestapoBar.swift` (строки 795–828).
- **Проблема:** Интерфейс `utun` в таблице маршрутизации может оставаться поднятым, даже если удаленный VPN-сервер завис или пакеты глушатся («зомби-туннель»).
- **Решение:** Фоновый воркер каждые 5 секунд отправляет ICMP Echo пакет: `/sbin/ping -c 1 -W 1500 1.1.1.1`. Если 2 пинга подряд не прошли (`consecutivePingFails >= 2`), туннель признается мертвым -> мгновенное срабатывание Kill-Switch с причиной `"Завис VPN туннель (нет ответа на пинг)"`.

### 1.4. Раздельное туннелирование (Per-Target Split Tunneling)
- **Исходники:** `src/gestapo_core.py` (строки 959–999), `src/GestapoBar.swift` (строки 573–590).
- **Проблема:** При Split Tunneling через VPN идут только домены ИИ (`claude.ai`, `chatgpt.com`, `generativelanguage.googleapis.com`), а `1.1.1.1` и `default` идут через домашний `en0`. Текущий форк выдаст 100% ложных тревог.
- **Решение:**
  - Кэширование DNS (300 секунд) через асинхронный `getaddrinfo` (без передачи доменных имён в `/sbin/route`, чтобы избежать зависаний DNS при отвале сети).
  - Проверка `/sbin/route -n get <числовой_IP>` для каждого домена.
  - Условие: интерфейс целевого IP **обязан** начинаться на `utun`.

### 1.5. Проверка реального внешнего IP (`check_ip`)
- **Исходники:** `bin/check_ip.sh`, `src/GestapoBar.swift` (строки 2335–2380).
- **Решение:** Привязка curl к целевому интерфейсу: `curl -s --max-time 4 --interface <utun> https://api.ipify.org` с отображением реального выходного IP в интерфейсе чёлки и настроек.

### 1.6. Защита оконных GUI-приложений (Claude Desktop, ChatGPT, Antigravity)
- **Исходники:** `src/GestapoBar.swift` (строки 854–893), `src/gestapo_core.py` (строки 758–800).
- **Решение:**
  - Мониторинг `NSWorkspace.shared.runningApplications` по Bundle ID:
    - `com.anthropic.claudefordesktop` (Claude Desktop)
    - `com.openai.chat` (ChatGPT Desktop)
    - `com.google.antigravity` / `com.google.antigravity.ide` (Antigravity Desktop)
  - Ликвидация: `NSRunningApplication.forceTerminate()`, плюс точечный `pkill -9 -x`.

### 1.7. Непрерывный Kill-Switch (Level-Triggered Continuous Kill)
- **Устранение бага:** В текущем форке `if prevActive && !isVpn` срабатывает только один раз в момент перехода `true -> false`. Если агент запускается при **уже** выключенном VPN, он не уничтожается.
- **Решение:**
  - На первом тике (переход): тревога чёлки, звук, системный баннер, запись в лог.
  - На всех последующих тиках, пока `!isVpnActive`: тихий фоновый отстрел (`Continuous Kill`), моментально убивающий любой запущенный целевой процесс.

### 1.8. Системные уведомления macOS
- **Решение:** Отправка баннера через `osascript display notification` / `UNUserNotificationCenter` при срабатывании тревоги, чтобы пользователь видел аварию даже при работе на внешнем мониторе без встроенной чёлки.

---

## 2. Архитектура модулей в Coucou (Swift 6 Strict Concurrency)

Подсистема разделяется на 4 изолированных компонента:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             GestapoWatchdog                                 │
│  (@MainActor ObservableObject — единый фасад для SwiftUI и AppState)        │
└──────────────┬───────────────────┬───────────────────┬──────────────────────┘
               │                   │                   │
               ▼                   ▼                   ▼
┌────────────────────────┐┌─────────────────┐┌───────────────────────────────┐
│  GestapoNetworkWorker  ││GestapoPowerGuard││       GestapoAppHunter        │
│    (actor / utility)   ││   (@MainActor)  ││       (nonisolated)           │
│ 1. Route check (utun)  ││ 1. IOPMAssertion││ 1. NSRunningApplication (GUI) │
│ 2. PingWorker (ICMP)   ││ 2. Sleep/Wake   ││ 2. pkill -9 -x (CLI)          │
│ 3. DNS Cache & Split   ││ 3. Grace 10s    ││ 3. Continuous Kill Loop       │
│ 4. External IP probe   ││                 ││ 4. macOS Notifications        │
└────────────────────────┘└─────────────────┘└───────────────────────────────┘
```

1. **`GestapoPowerGuard` (`Sources/App/GestapoPowerGuard.swift`)**:
   - Управление `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)`.
   - Подписка на `willSleepNotification` и `didWakeNotification`.
   - Вычисление 10-секундного Grace Period (`isGracePeriodActive`).
2. **`GestapoNetworkWorker` (`Sources/App/GestapoNetworkWorker.swift`)**:
   - Swift `actor` для безопасной фоновой сетевой работы.
   - Метод `checkStatus(...)` -> `NetworkSnapshot` (глобальный туннель, split-домены, пинг, latency).
   - Асинхронный метод `probeExternalIp(...)`.
3. **`GestapoAppHunter` (`Sources/App/GestapoAppHunter.swift`)**:
   - Структура `GestapoTargetApp` (CLI и GUI цели).
   - Метод `killAllActiveTargets(...)` с белым списком от самоубийства (`coucou`, `notchbuddy`, `terminal`, `zsh`).
   - Метод `sendMacNotification(...)` для системных баннеров.
4. **`GestapoWatchdog` (`Sources/App/GestapoWatchdog.swift`)**:
   - Реактивный `@MainActor` координатор.
   - Обработка тиков: переход на непрерывный Level-Triggered kill-switch.

---

## 3. Изменения в интерфейсе чёлки (Dynamic Island)

### 3.1. Доработка экрана тревоги `SecurityPanicView` (`IslandViewContent.swift`)
- Блокировка кнопки **"Сбросить тревогу"** по единому `protectionStatus`: она недоступна при dead tunnel, split-tunnel утечке, прямом интерфейсе, grace period и выключенной защите.
- Текстовая подсказка: *"VPN не восстановлен — сброс заблокирован"*; карточка щитка показывает причину и интерфейс утечки.

### 3.2. Вынос Gestapo из чувачков: иконка щитка в шапке чёлки и меню защитника
Gestapo — это не сессия агента Claude/Codex, поэтому он убирается из карусели чувачков (Mochi pills) и превращается в системный элемент статуса.

1. **Кнопка-щиток в шапке чёлки (`IslandRootView.swift`):**
   - Размещается в правом блоке хедера рядом с шестерёнкой настроек (`gearshape`):
     ```swift
     Button(action: {
         withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
             state.view = (state.view == .gestapoShield ? .overview : .gestapoShield)
         }
     }) {
         Image(systemName: watchdog.isVpnActive ? "shield.fill" : "exclamationmark.shield.fill")
             .font(.system(size: 14))
             .foregroundColor(watchdog.isVpnActive ? Color(hex: "#30D158") : Color(hex: "#FF5460"))
     }
     ```
   - Динамический цвет щитка:
     - 🟢 **Зеленый (`#30D158`)**: VPN активен (`utun*`), защита на страже.
     - 🟡 **Желтый (`#FFD60A`)**: Sleep/Wake Grace Period (переподключение после открытия крышки Mac).
     - 🔴 **Красный (`#FF5460`)**: VPN упал, защита сработала / активен аварийный режим.

2. **Экран защитника в чёлке (`GestapoShieldIslandView` в `IslandViewContent.swift`):**
   - Открывается прямо в чёлке по клику на щиток (по аналогии с экраном настроек `SettingsIslandView`).
   - Содержит:
     - **Текущий статус сети:** `VPN активен` / `Прямой интернет (en0)`, имя интерфейса (`utun3`), шлюз.
     - **Проверка внешнего IP (СТРОГО ON-DEMAND):**
       - Фоном curl НЕ крутится и не разряжает батарею!
       - Кнопка **«Проверить IP»** запускает асинхронную проверку выбранной цели (по умолчанию `claude.ai`): резолвится домен, определяется его маршрут и интерфейс, затем выбирается один из `ifconfig.me`, `icanhazip.com`, `api.ipify.org` или `checkip.amazonaws.com`, доступный через тот же интерфейс; запрос `curl` явно привязывается к этому `utun`.
       - В карточке отображаются целевой IP, интерфейс цели, выбранный IP-сервис и полученный внешний IP. Страна не определяется: пользователь сравнивает IP с адресом своего VPN.
     - **Статус защиты от засыпания:** индикатор `Mac не уснёт` отражает активный `IOPMAssertion`.
     - **Переход к настройкам:** кнопка «Настройки» открывает существующий экран настроек; вкладка `Gestapo Guard` будет добавлена в Фазе 4.
     - **Кнопка «Журнал»:** открывает `~/Library/Logs/Gestapo/watchdog.log`.
3. **Очистка `PillCatalog.swift`:**
   - Плашка `gestapo_shield` удаляется из каталога тасок агентов, чтобы не засорять переключатели рабочих сессий.

---

## 4. Новая секция в настройках: `Gestapo Guard` (`SettingsView.swift`)

В сайдбар окна настроек добавляется вкладка **Gestapo Guard** (`icon: "shield.checkered"`, цвет `#30D158`).

### Содержимое секции:
1. **GroupBox «Статус защиты и сетевой шлюз»**:
   - Индикатор: `🟢 Защищён (utun3)` или `🔴 Утечка (en0)`.
   - Внешний IP с кнопкой `Проверить IP`.
   - Задержка пинга и статистика потерь пакетов.
2. **GroupBox «Политика Kill-Switch»**:
   - `Toggle("Включить сторож Gestapo (Kill-Switch активен)", isOn: $isEnabled)`
   - `Toggle("Непрерывный отстрел (Continuous Kill)", isOn: $continuousKill)` — подавляет повторный запуск агентов при отключенном VPN.
   - `Toggle("Мониторинг зависшего туннеля (ICMP Ping каждые 5 с)", isOn: $pingCheckEnabled)`
   - `Toggle("Проверка Split-Tunneling доменов (claude.ai, chatgpt.com, gemini)", isOn: $splitTunnelCheck)`
3. **GroupBox «Управление питанием и крышкой Mac (Power Guard)»**:
   - `Toggle("Защита от сна при блокировке экрана (IOPMAssertion)", isOn: $preventSleep)` — позволяет Mac выполнять задачи при заблокированном экране (`Cmd+Ctrl+Q`).
   - `Toggle("Sleep/Wake Guard (10-секундный Grace Period при открытии крышки)", isOn: $sleepWakeGuardEnabled)`
4. **GroupBox «Защищаемые приложения и агенты»**:
   - Консольные агенты: чекбоксы для `claude`, `agy`, `codex`, `gemini`, `cursor-agent`.
   - Оконные GUI-приложения: чекбоксы для `Claude Desktop (.app)`, `ChatGPT Desktop (.app)`, `Antigravity (.app)`.
5. **GroupBox «Оповещения и аудит»**:
   - `Toggle("Системный звук при аварии", isOn: $alarmSoundEnabled)`
   - `Toggle("Баннеры Центра уведомлений macOS", isOn: $macNotificationsEnabled)`
   - Кнопка `Открыть журнал аудита (watchdog.log)`
   - Кнопка `Симуляция аварии VPN` (для проверки работы).

---

## 5. Фазы реализации и критерии приёмки (DoD)

| Фаза | Задачи | Критерии приёмки (DoD) |
|---|---|---|
| ✅ **Фаза 1: Сетевое ядро и Power Guard** | Реализованы `GestapoPowerGuard.swift`, `GestapoNetworkWorker.swift` и continuous kill в `GestapoWatchdog.swift`: IOPM assertion, sleep/wake grace period, ICMP ping, split-tunnel route checks, DNS cache и on-demand IP probe. | Safe Swift/Python тесты проходят; проект собирается Swift 6. |
| ✅ **Фаза 2: GUI Hunter и уведомления** | Реализованы `NSRunningApplication.forceTerminate` для GUI, точный `pkill -9 -x` для CLI, безопасный whitelist, AppleScript escaping и асинхронные системные баннеры. Добавлены безопасные тестовые seams. | 4/4 Phase 2 safe-теста проходят; полный macOS build успешен. |
| ✅ **Фаза 4: Вкладка настроек Gestapo Guard** | Добавление вкладки в сайдбар `SettingsView.swift`. Верстка 5 GroupBox с тумблерами и кнопкой проверки IP. | Все тумблеры сохраняются в `@AppStorage`. Кнопка «Проверить IP» показывает реальный IP без зависания UI. |
| **Фаза 5: Тестирование и валидация** | Расширение `tests/GestapoWatchdogTests.swift` (Grace period, Ping Dead Tunnel, Continuous Kill, GUI). Прогон `./scripts/test-gestapo.sh`. | Все тесты завершаются со статусом PASS. Сборка `xcodebuild` проходит без ошибок. |

Фазы 1-4 закрыты. Вкладка Gestapo Guard в SettingsView реализована и привязана к AppStorage и GestapoWatchdog. Safe-тесты и сборка проходят без ошибок.
