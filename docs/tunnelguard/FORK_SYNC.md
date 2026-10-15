# Руководство по обновлению и синхронизации форка

Этот репозиторий является форком официального проекта **Coucou (NotchBuddy)** ([Louis-CFM/coucou](https://github.com/Louis-CFM/coucou)). В ветку `tunnelguard-notch` интегрирован защитный контур **TunnelGuard** (VPN Watchdog, Kill-Switch, экран тревоги чёлки и адаптация сборки без платных подписей Apple Developer).

В этом документе описан регламент регулярной синхронизации нашего форка с апстримом (upstream).

---

## 1. Конфигурация Git Remotes

Убедитесь, что в локальном репозитории настроены оба удалённых источника:

```bash
git remote -v
```

Должно отображаться:
- `origin` — наш форк: `https://github.com/ShlykovPavel/ai_helper_adaptation.git`
- `upstream` — оригинальный репозиторий: `https://github.com/Louis-CFM/coucou.git`

Если `upstream` отсутствует, добавьте его:
```bash
git remote add upstream https://github.com/Louis-CFM/coucou.git
git remote set-url --push upstream DISABLE   # Защита от случайного пуша в апстрим
```

---

## 2. Структура веток

- `main` — зеркало оригинальной ветки `upstream/main`.
- `tunnelguard-notch` — наша основная рабочая ветка с функционалом TunnelGuard и адаптацией для локального запуска на Mac.

---

## 3. Пошаговый процесс обновления

### Шаг 1. Получение свежих коммитов из upstream
```bash
git fetch upstream --tags
```

### Шаг 2. Обновление локальной ветки `main` (опционально, для чистоты)
```bash
git checkout main
git merge upstream/main --ff-only
git push origin main
```

### Шаг 3. Переход в рабочую ветку `tunnelguard-notch`
Перед слиянием убедитесь, что в рабочей директории нет незакоммиченных изменений:
```bash
git checkout tunnelguard-notch
git status
```

### Шаг 4. Слияние изменений из upstream
Рекомендуемый подход — слияние через `git merge`:
```bash
git merge upstream/main
```
*(Также возможен `git rebase upstream/main`, если требуется линейная история коммитов перед созданием PR, но для стабильной синхронизации форка `git merge` более безопасен и предсказуем).*

---

## 4. Разрешение конфликтов: что важно сохранить

При возникновении конфликтов слияния обратите особое внимание на файлы, в которых реализован наш функционал:

| Файл | Что в нем изменено (НЕ ЗАТИРАТЬ апстримом!) |
|---|---|
| [`NotchBuddy/project.yml`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/project.yml) | **КРИТИЧНО**: В upstream используются сертификаты `Apple Development`, `DEVELOPMENT_TEAM: 256AUJ9555` и таргеты `CoucouAppStore`. В нашем форке отключена подпись (`CODE_SIGNING_REQUIRED: NO`, `CODE_SIGN_IDENTITY: ""`), убраны AppStore схемы. **Сохраняйте нашу конфигурацию**, иначе проект не соберется без сертификата разработчика! |
| [`NotchBuddy/Sources/App/TunnelGuardWatchdog.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/TunnelGuardWatchdog.swift) | Наш новый файл. Должен оставаться нетронутым. |
| [`NotchBuddy/Sources/App/HookServer.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/HookServer.swift) | Содержит шаблон `nbHookPythonGitHub` со шлагбаумом TunnelGuard (`verify_vpn_route_utun`, `tunnel_guard_kill_agent_and_exit`) и Fail-Closed обертку `nbHookShellWrapper`. |
| [`NotchBuddy/Sources/App/AppState.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/AppState.swift) | Содержит методы `triggerSecurityPanic` и `resetSecurityAlert`, а также свойство `securityAlarmText`. |
| [`NotchBuddy/Sources/App/AppDelegate.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/AppDelegate.swift) | Вызовы `TunnelGuardWatchdog.shared.start()` и `stop()`, а также замыкания `MainActor.assumeIsolated`. |
| [`NotchBuddy/Sources/CoucouKit/IslandTypes.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/CoucouKit/IslandTypes.swift) | Перечисление `IslandView.securityPanic` и его параметры верстки/цвета в `IslandConst`. |
| [`NotchBuddy/Sources/CoucouKit/PillCatalog.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/CoucouKit/PillCatalog.swift) | Декларация плашки `tunnelguard_shield`. |
| [`NotchBuddy/Sources/App/IslandViewContent.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/IslandViewContent.swift) | Структура `SecurityPanicView`. |
| [`NotchBuddy/Sources/App/BotCanvasView.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/BotCanvasView.swift) | Адаптация Swift 6 Concurrency (модификаторы наблюдателей состояния). |
| [`NotchBuddy/Sources/App/IslandWindowController.swift`](file:///Users/pavel/ai_helper_adaptation/NotchBuddy/Sources/App/IslandWindowController.swift) | Селектор `handleDidActivateApplication` и вызовы `MainActor.assumeIsolated`. |

---

## 5. Обязательная регенерация проекта (XcodeGen)

> **ВАЖНО!**  
> Проект `NotchBuddy.xcodeproj` **никогда не редактируется вручную**. Он генерируется автоматически из файла `project.yml` утилитой `xcodegen`.

После завершения слияния и разрешения конфликтов выполните:

```bash
cd NotchBuddy
xcodegen
cd ..
```

XcodeGen заново пересоберет структуру `NotchBuddy.xcodeproj/project.pbxproj` с учетом обновленных исходников и наших настроек `project.yml`.

---

## 6. Проверочная сборка

Убедитесь, что проект собирается без ошибок:

```bash
cd NotchBuddy
xcodebuild -scheme NotchBuddy -configuration Debug build
cd ..
```

Если сборка завершилась статусом `** BUILD SUCCEEDED **`, всё в порядке.

---

## 7. Фиксация и отправка в origin

```bash
git add .
git commit -m "chore(sync): merge upstream changes into tunnelguard-notch"
git push origin tunnelguard-notch
```
