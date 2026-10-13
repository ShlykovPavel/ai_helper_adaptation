# Gestapo Security Gate & VPN Watchdog

Подсистема **Gestapo** — это модуль безопасности и аварийного отключения (Kill-Switch) для AI-агентов (Claude Code, Antigravity/AGY, Codex, Gemini CLI, Cursor Agent), интегрированный в приложение **NotchBuddy (Coucou)**.

---

## 1. Назначение и концепция

При работе локальных AI-агентов критически важно гарантировать, что чувствительный исходный код, переменные окружения, промты и токены отправляются во внешние LLM API **исключительно через защищённый VPN-туннель**.

Если VPN внезапно падает (разрыв сессии, сбой демона, сброс сетевого маршрута), стандартные сетевые сокеты macOS автоматически переключаются на основной незащищённый интерфейс (`en0`/Wi-Fi/Ethernet). В этот момент любой запрос агента может уйти в открытый интернет.

### Задачи Gestapo:
1. **Мгновенный перехват и блокировка действий агентов (L1 Gate)**: ни один сетевой вызов или выполнение инструмента (tool call) не должны пройти при отсутствии активного VPN.
2. **Аппаратная принудительная ликвидация (Kill-Switch)**: мгновенный `SIGKILL` процессам агентов при отключении VPN.
3. **Фоновый непрерывный мониторинг (L2 Watchdog)**: опрос сетевой таблицы маршрутизации macOS с низкими накладными расходами.
4. **Визуальная индикация в Notch / Dynamic Island**: чёлка MacBook моментально раскрывается в аварийный экран тревоги `GESTAPO SECURITY ALARM` со звуковым оповещением.
5. **Аудит безопасности**: запись всех инцидентов и восстановлений в локальный лог с авторотацией.

---

## 2. Архитектура: двухэшелонная оборона

Gestapo реализует концепцию **Defense in Depth** (эшелонированная защита) на двух независимых уровнях:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AI Agent (Claude / AGY / etc.)                  │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Запрос инструмента (Tool Use)
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ [L1] HOOK RELAY GATE (nb-hook.py & wrapper)                            │
│  1. /sbin/route -n get 1.1.1.1 (проверка utun*)                       │
│  2. Если VPN нет:                                                      │
│     ├── Ответ в stdout: {"permissionDecision": "deny", ...}            │
│     ├── SIGKILL группе процессов агента (os.killpg)                    │
│     └── exit 1 (Fail-Closed)                                           │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ VPN активен (utun*)
                                     ▼
                        [Unix Socket / coucou.sock]
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ [L2] NOTCHBUDDY APP / BACKGROUND WATCHDOG (GestapoWatchdog.swift)      │
│  ├── Таймер: каждые 1.5 с в RunLoop.main (.common)                    │
│  ├── Проверка: nonisolated /sbin/route                                 │
│  ├── Edge-Trigger: отслеживание перехода (Active -> Inactive)         │
│  ├── Авария:                                                           │
│  │    ├── AppState: тревога, раскрытие чёлки (.securityPanic)          │
│  │    ├── Аудио: системный сигнал NSSound.beep()                       │
│  │    ├── Kill-Switch: /usr/bin/pkill -9 -x <агенты>                   │
│  │    └── Лог: ~/Library/Logs/Gestapo/watchdog.log                     │
│  └── Восстановление: автоматический сброс тревоги при возврате VPN     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Где встроен функционал (Компоненты кодовой базы)

| Файл | Роль в подсистеме Gestapo |
|---|---|
| [`NotchBuddy/Sources/App/GestapoWatchdog.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/GestapoWatchdog.swift) | Фоновый демон-сторож: опрос сетевых интерфейсов, edge-triggered детекция падений VPN, ликвидация через `pkill`, ротация логов. |
| [`NotchBuddy/Sources/App/HookServer.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/HookServer.swift) | Генератор скриптов хука (`nb-hook.py`, шелл-обертка): "Шлагбаум Гестапо", поиск реального PID агента, fail-closed блокировка. |
| [`NotchBuddy/Sources/App/AppDelegate.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/AppDelegate.swift) | Жизненный цикл: `GestapoWatchdog.shared.start()` при старте, `stop()` при завершении приложения. |
| [`NotchBuddy/Sources/App/AppState.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/AppState.swift) | Реактивное состояние: поля `securityAlarmText`, методы `triggerSecurityPanic(...)` и `resetSecurityAlert()`. |
| [`NotchBuddy/Sources/CoucouKit/IslandTypes.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/CoucouKit/IslandTypes.swift) | Типы представления: новый экран `case securityPanic`, геометрия и цвет тревоги (`rgba(244,80,94,0.7)`). |
| [`NotchBuddy/Sources/CoucouKit/PillCatalog.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/CoucouKit/PillCatalog.swift) | Декларация плашки `gestapo_shield` ("Gestapo Shield" / "VPN Guard") для отображения статуса защиты в интерфейсе. |
| [`NotchBuddy/Sources/App/IslandViewContent.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/IslandViewContent.swift) | SwiftUI-компонент `SecurityPanicView`: отрисовка красной карточки тревоги со щитом и кнопкой сброса. |

---

## 4. Как это работает в деталях

### 4.1. Детектирование VPN-туннеля (macOS Routing Table)

И в Swift (`GestapoWatchdog`), и в Python (`nb-hook.py`) проверка VPN выполняется через опрос системной таблицы маршрутизации macOS с помощью утилиты `/sbin/route`:

```bash
/sbin/route -n get 1.1.1.1
```

Если целевой маршрут к внешнему IP проходит через виртуальный туннельный интерфейс (начинающийся на **`utun`**, например `utun0`, `utun3`), соединение считается защищённым. Если нет, дополнительно проверяется маршрут по умолчанию (`default`):

```bash
/sbin/route -n get default
```

Если ни один из маршрутов не указывает на `utun*`, фиксируется отсутствие VPN.

> **Почему `utun`?**  
> В macOS практически все современные VPN-клиенты (WireGuard, OpenVPN, Tailscale, IPSec, Cisco AnyConnect, Cloudflare WARP) создают интерфейсы вида `utun0..utun9`.

### 4.2. Контур L1: Шлагбаум в Hook Relay (`HookServer.swift` -> `nb-hook.py`)

Когда AI-агент собирается выполнить команду (событие `PreToolUse`), он вызывает локальный хук `~/.claude/hooks/coucou-hook.sh`:

1. **Мгновенная проверка до чтения `stdin`**:  
   Хук первым делом вызывает `verify_vpn_route_utun()`. Таймаут команды жестко ограничен `0.3` сек.
2. **Определение истинного PID агента (`get_real_agent_pid`)**:  
   Скрипт хука запускается как дочерний процесс. Чтобы убить не только сам хук, но и вызвавший его процесс агента (Claude, Node, AGY), функция обходит дерево процессов вверх по PPID (до 10 уровней) и находит целевой бинарник.
3. **Fail-Closed ответ и ликвидация**:  
   - В `stdout` выводится JSON с отказом в разрешении:
     ```json
     {
       "hookSpecificOutput": {
         "hookEventName": "PreToolUse",
         "permissionDecision": "deny",
         "message": "🚨 [GESTAPO] VPN ОТКЛЮЧЕН! Действие заблокировано."
       }
     }
     ```
   - Отправляется немедленный жесткий сигнал `SIGKILL` (`kill -9`) всей группе процессов агента (`os.killpg(os.getpgid(agent_pid), signal.SIGKILL)`).
   - Скрипт завершается с кодом `exit 1`.
4. **Поведение оболочки (`nbHookShellWrapper`)**:  
   Шелл-скрипт больше не подавляет ошибки (раньше Coucou всегда выходил с 0). Теперь при ошибке он немедленно завершается с `exit $rc`, гарантируя прерывание выполнения команды агентом.

### 4.3. Контур L2: Фоновый Watchdog (`GestapoWatchdog.swift`)

Фоновый процесс обеспечивает защиту в моменты, когда агент не выполняет хуки (например, ожидает ответа пользователя или генерирует код):

1. **Таймер на 1.5 секунды**:  
   Работает в `RunLoop.main` с режимом `.common`. Это предотвращает остановку таймера, если пользователь зажал системное меню macOS или открыл модальное окно.
2. **Асинхронность и Swift 6 Concurrency**:  
   Сетевой вызов выполняется в фоновой очереди `DispatchQueue(label: "com.gestapo.coucou.watchdog")` через `nonisolated` методы, не блокируя UI и рендеринг чёлки.
3. **Edge-Triggered активация**:  
   Ликвидация и звуковой сигнал срабатывают **только на переходе** из состояния `true` в `false`. Это исключает бесконечный шквал `pkill` и системных звуков, пока VPN отключен.
4. **Target Kill List**:  
   При падении VPN вызывается утилита `/usr/bin/pkill -9 -x` для строгого списка процессов:
   - `claude` (Claude Code CLI)
   - `agy` (Antigravity CLI)
   - `codex` (Codex CLI)
   - `gemini` (Gemini CLI)
   - `cursor-agent` (Cursor Background Agent)
   *(Флаг `-x` гарантирует точное совпадение имени процесса, исключая случайное завершение посторонних программ).*
5. **Логирование и ротация**:  
   События пишутся в `~/Library/Logs/Gestapo/watchdog.log`. Если размер файла превышает 5 МБ, он автоматически ротируется в `watchdog.log.old`.

### 4.4. Индикация в чёлке (Dynamic Island)

При активации тревоги:
1. `AppState.shared.triggerSecurityPanic(...)` выставляет:
   - `view = .securityPanic`
   - `mode = .expanded`
   - `stateOverride = .error`
2. Окно чёлки распахивается до высоты 160 pt с ярко-красным свечением.
3. Отображается экран `SecurityPanicView`:
   - Иконка `exclamationmark.shield.fill`.
   - Заголовок `GESTAPO SECURITY ALARM`.
   - Текст ошибки с причиной блокировки.
   - Кнопка **"Сбросить тревогу"** для ручного возврата в нормальный режим после включения VPN.
4. При повторном поднятии VPN (`utun*`) сторож автоматически вызывает `resetSecurityAlert()`, сворачивая чёлку обратно в компактный режим.

---

## 5. Проверка работы и отладка

### Просмотр логов Gestapo
```bash
tail -f ~/Library/Logs/Gestapo/watchdog.log
```

Пример вывода при инциденте:
```text
2026-10-13 11:46:25 [GESTAPO_WATCHDOG] 🚨 [KILL-SWITCH] VPN упал! Обнаружен интерфейс: en0. Немедленная ликвидация агентов.
2026-10-13 11:47:10 [GESTAPO_WATCHDOG] 🟢 [WATCHDOG] VPN туннель восстановлен: utun3
```

### Тестирование срабатывания
1. Запустите приложение NotchBuddy / Coucou.
2. Запустите сессию любого агента (`claude` или `agy`).
3. Отключите VPN-клиент.
4. **Ожидаемый результат**:
   - Раздастся звуковой сигнал `beep`.
   - Процесс агента в терминале мгновенно завершится (Killed: 9).
   - Чёлка раскроется в красный экран тревоги с сообщением `VPN отключен! AI-агенты принудительно ликвидированы.`
   - В `~/Library/Logs/Gestapo/watchdog.log` появится запись инцидента.
5. Включите VPN обратно.
6. Чёлка автоматически свернётся, в лог запишется восстановление туннеля.
