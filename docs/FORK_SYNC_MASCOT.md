# Архитектура интеграции маскота и руководство по синхронизации форка (Fork Sync Guide)

## 1. Проблема синхронизации форка

Репозиторий `ai_helper_adaptation` является форком апстрим-проекта **Coucou / NotchBuddy** (автор Louis Raille). Апстрим регулярно обновляется: добавляются новые интеграции, экраны, оптимизации и исправления.

### Риск наивной реализации:
Если мы заменим отрисовку Мочи «в лоб» внутри десятков существующих файлов (`IslandRootView.swift`, `FlowPill.swift`, `SpotifyViews.swift`, `engine.ts` и т.д.), то при первой же команде:
```bash
git fetch upstream && git merge upstream/main
```
мы получим **десятки сложнейших конфликтов слияния (merge conflicts)**, которые придется вручную распутывать часами, рискуя сломать логику острова.

---

## 2. Аудит зон присутствия маскота в кодовой базе

В кодовой базе персонаж используется в **8 ключевых контекстах**. Ниже приведена полная карта точек входа:

| № | Зона UI | Файл в репозитории | Размер / Параметры | Назначение |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **Свёрнутая чёлка (Compact)** | `NotchBuddy/Sources/App/IslandRootView.swift:377` | `diameter: 20pt` (Canvas ~33pt) | Главный аватар в закрытом островке |
| **2** | **Раскрытая чёлка (Expanded)** | `NotchBuddy/Sources/App/IslandRootView.swift:380` | `diameter: 44–66pt` (avg 58pt) | Аватар в детальном окне задачи / approval |
| **3** | **Пиллы сессий и агентов** | `NotchBuddy/Sources/App/FlowPill.swift:474`<br>`NotchBuddy/Sources/App/BotCanvasView.swift:249` | `diameter: 16–20pt` (`isMini: true`) | Микро-аватар рядом со статусом каждого агента |
| **4** | **Интеграции (Музыка / Голос)** | `NotchBuddy/Sources/App/SpotifyViews.swift:34`<br>`NotchBuddy/Sources/App/Voice/VoiceResultView.swift:18` | Танцующий / пульсирующий мод | Реакция на ритм Spotify и уровень микрофона |
| **5** | **Итоги недели (Weekly Recap)** | `NotchBuddy/Sources/App/WeeklyRecapView.swift:203` | Статичный снимок | Карточка с итогами работы за неделю |
| **6** | **Хаб и Настройки (FlowHub)** | `NotchBuddy/Sources/App/FlowHubMochis.swift:65` | `diameter: 96–160pt` (Hero) | Витрина стилей и нарядов |
| **7** | **Десктопный компаньон** | `NotchBuddy/Sources/App/DesktopMochi.swift:28` | Плавающее окно | Маскот, летающий по экрану монитора |
| **8** | **iPhone / Dynamic Island** | `NotchBuddy/Sources/Widgets/MochiLiveActivity.swift`<br>`NotchBuddy/Sources/Phone/MochiLive.swift` | Виджеты Live Activity | Отображение на экране блокировки iOS |
| **9** | **Windows / Linux (Tauri)** | `windows/src/island/island.ts`<br>`windows/src/mochi/minibots.ts` | 2D Canvas | Версия островка под Windows и Linux |

---

## 3. Архитектурный паттерн: Facade / Adapter (`MascotHostView`)

Чтобы изолировать наши доработки от апстрима, мы применяем паттерн **Фасад / Адаптер**:

```
                       ┌──────────────────────────────────────────────┐
                       │          Апстримный код Coucou               │
                       │  (IslandRootView, FlowPill, SpotifyViews...) │
                       └──────────────────────┬───────────────────────┘
                                              │ (вызывает существующий)
                                              ▼
                       ┌──────────────────────────────────────────────┐
                       │              BotCanvasView                   │
                       │          (ТОНКИЙ ФАСАД-ПЕРЕХВАТЧИК)          │
                       └──────────────────────┬───────────────────────┘
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
      [ UserDefaults: .mochi ]                       [ UserDefaults: .shapeshifter ]
                      │                                               │
                      ▼                                               ▼
         ┌─────────────────────────┐                     ┌─────────────────────────┐
         │     BotEngine.swift     │                     │   ShapeshifterEngine    │
         │  (Оригинальный код)     │                     │  (НАШ НОВЫЙ МАСКОТ)     │
         │  *Ни строчки правок*    │                     │  *В отдельной папке*    │
         └─────────────────────────┘                     └─────────────────────────┘
```

### Принципы реализации паттерна:
1. **Изолированный модуль**:
   Весь код нового маскота складывается в отдельную директорию:
   * macOS: `NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/`
   * Windows: `windows/src/mascot/`
   В этих папках лежат: спрайты, контроллер анимаций и отрисовщик ядер.
2. **Нулевое изменение сигнатур вызовов**:
   Мы не меняем имена компонентов в местах вызова (`BotPlacement`, `FlowPill` и т.д.). Компонент `BotCanvasView` остается точкой входа, но внутри себя делает прозрачную развилку:
   ```swift
   struct BotCanvasView: View {
       @ObservedObject var state: AppState
       // ...
       var body: some View {
           if AppSettings.activeMascot == .shapeshifter {
               ShapeshifterHostView(state: state, sizeVariant: resolveSize(state))
           } else {
               OriginalBotCanvasView(state: state) // нетронутый код автора
           }
       }
   }
   ```
3. **Единый контракт размера (LOD)**:
   ```swift
   enum MascotSizeVariant {
       case compact   // 20-32pt: неоновый контур + цветная точка ИИ
       case expanded  // 44-66pt: 3D-тело с логотипом в животе + предметы
       case hero      // 96-160pt: крупный аватар для Хаба
   }
   ```

---

## 4. Пошаговый регламент обновления форка (Fork Sync Checklist)

Когда в апстрим-репозитории `louisraille/coucou` выходит новая версия:

### Шаг 1. Получение изменений апстрима
```bash
git fetch upstream
git checkout -b sync-upstream-vXX
git merge upstream/main
```

### Шаг 2. Разрешение конфликтов (минимальное)
Так как оригинальные файлы Мочи (`BotEngine.swift`, `MochiOutfitDrawing.swift`) не модифицировались, а наш код лежит в изолированной папке `Sources/CoucouKit/Mascots/`, конфликтов будет **ноль** или они ограничатся 1–2 строчками в фасаде `BotCanvasView.swift`.

### Шаг 3. Добавление маскота в новые экраны апстрима
Если в новой версии автор добавил новый экран (например, новый виджет в чёлке):
1. Проверяем, как там вызывается персонаж (обычно это `BotCanvasView` или `MiniBotCanvasView`).
2. Так как наш фасад перехватывает эти вызовы автоматически — **новый экран сразу же получит нашего маскота без написания нового кода!**

### Шаг 4. Проверка и билд
```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build
cd ../windows && npm run tauri dev
```
