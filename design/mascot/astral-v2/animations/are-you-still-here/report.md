# Отчёт: «Ты ещё тут?»

16 октября 2026. Статус: черновой пробный цикл для ревью.

## Результат

32 уникальных рисунка imagegen сохранены; все 32 используются в таймлайне. 96 тактов / 24 fps =4.000 с, номинально 8 новых поз/с. Интерполяции нет; повторы не считаются новыми рисунками.
Рисунок 0:4 такта (3 в начале+1 в конце); рисунок 31:2 такта; остальные:3. WebP/GIF имеют 33 последовательных блока и реальную длительность 4000 мс. Моргание: рисунок 22 (23-й при счёте с 1), 2.750–2.875 с,125 мс.
Канонический мастер и runtime не изменены. Интеграция в приложение не выполнялась.

## Журнал генерации и проверки

1. Прочитаны CLAUDE.md, design/mascot/AGENTS.md, docs/MASCOT_DESIGN_SPEC.md, docs/MASCOT_HANDOFF.md, imagegen/SKILL.md. Мастер открыт через view_image. Работа в ветке tunnelguard-notch.
2. Built-in imagegen создал 8 ключевых поз. После раннего ревью зафиксированы близкие к телу лапки, короткое моргание, честный статус стыка.
3. Built-in imagegen создал два листа по 16 поз,1254×1254 RGBA. Для второго первый лист использован дополнительным референсом. Исходники сохранены без правок. CLI/API fallback не использовался.
4. Строгая нарезка по четвертям слегка обрезала нижнюю волну: сетка imagegen не идеально регулярная. Расширение кропов могло захватывать соседей. Исправлено поиском настоящих прозрачных промежутков.
5. Ревью выявило дрейф центра между рядами. Исправлено переносом целого рисунка на общий холст, без деформации тела. Один общий ресемплинг ячейки 350→384. ЯкорьX192,Y192→182→192 в первой половине, во второйY192. Исходные crop/virtualCell/translation/targetAnchor сохранены в atlas.json.
6. Проверка полногоRGBA уточнена: PNG/atlas сравниваются побайтово; alpha/края/bbox пересчитываются из реальныхPNG. ДиагностическийRGBA diff использует alpha_only=False.
7. Браузерный просмотр на 8773: пауза работает; ползунок 66 показывает 2.750 с/такт 67/рисунок 23; следующий шаг 2.792 с/такт 68/тот же рисунок. Моргание видно на светлом/тёмном фоне и 26/64 px. Такт 95 показывает 3.958 с/рисунок 1; следующий шаг 0.000 с/рисунок 1. Снимок browser-blink-review.png. Локальный сервер 8773 этой проверки остановлен; сервер основного агента 8767 не затронут.

## Проверки

```sh
python3 scripts/pack-astral-idle.py
python3 scripts/pack-astral-idle.py --check
```

Использованы Python3/Pillow12.2.0. Проверены 32 уникальныхSHA-256,32 PNG384×384 RGBA с прозрачностью, отсутствие видимой обрезки, полное побайтовое совпадениеPNG/atlas, якоря и 96 тактов=4 с. WebP/GIF декодируются; длительность каждого 4000 мс. Машинный результат verification.json.
Центр 15→16: ΔX+1 px/ΔY0;31→0:ΔX0/ΔY+0.5 px. Допуск округления±0.5 px. maxBorderAlpha1/255; видимого силуэта на границе нет.
Основной агент и независимый reviewer подтвердили текущую упаковку до написания этого отчёта.

## Ограничения

- 8 новых поз/с с удержанием дают ступенчатость;24 уникальных рисунка/с не достигнуты.
- Подъём 10 px задаёт общий путь при упаковке. Лапки, волны, веки, поворот и силуэт меняются в самих рисунках, не CSS-деформациями.
- Любопытный наклон во второй половине слабый.
- Между рисунками остаётся вариативность света, лица и размеров. Выравнивание исправляет только дрейф расположения в сетке.
- Стык 31→0 сохраняет изменение ширины 288→264 px(~8%) и высоты 292→281 px(~4%). Точный повтор начального рисунка замыкает позицию, но художественной бесшовности пока нет.
- 384 pxэкспорта получены общим увеличением ячейки 350 px, новой детализации нет.
- GIF на светлой подложке имеет ограниченную палитру; PNG/WebP сохраняют альфу.
- HTML-проба не подтверждает native-интеграцию, native-производительность или совместимость с текущим горизонтальным загрузчиком.

## Точные использованные промпты

Во всех вызовах transparent_background=true. Порядок референсов и SHA-256 в generation.json.

### key-poses

```text
Use case: identity-preserve.
Asset type: transparent key-pose sheet for an actual frame-by-frame 4-second idle animation of Astral Morph, called "Are you still here?".
Input image 1 is the identity reference, NOT a background. Preserve this exact icy pearl frosted glass ghost character: rounded dome, two small paw flippers, exactly three soft lower scallops, exactly two glowing white vertical oval eyes. Soft upper-left studio illumination, pale silver-blue glass with subtle lilac/cyan edges. No pupils, no mouth, no nose, no blush, no inner core, no logos, no props, no shadow or floor.
Create ONE image with exactly 8 separate complete poses in a strict 4-column by 2-row regular grid. All 8 cells have the same dimensions and same fixed camera, body scale, eye size and lighting. Keep at least 12% fully transparent padding inside every cell. True alpha background, no checkerboard drawn, no cell borders, no text, no labels.
Read order left-to-right then next row, these are successive key poses: 1 neutral front looking at viewer, 2 gently risen 3% with paws hanging slightly lower and lower scallops swaying, 3 risen and starting a subtle 12-degree turn toward image-right with one paw slightly behind, 4 small three-quarter turn right only 18 degrees (both eyes visible), 5 returning front with a curious 6-degree lean (genuine changed body silhouette and asymmetric paws), 6 same curious lean with both eyes closed into soft short white eyelid arcs (one blink), 7 front eyes open, gently squashed body with three lower scallops flexed, 8 restored toward neutral front to close a loop. These must be genuinely redrawn coherent poses, not repeated copies moved around. Tiny gentle motion, maintain original identity and face spacing. Rendered game character sprites, clean isolated alpha. No decorative elements.
```

### part-1

```text
Use case: identity-preserve.
Asset type: true transparent sprite sheet; part 1 of a gentle 4-second idle loop, 16 real consecutive animation drawings covering time 0.000 to 1.875 s, each held for 125 ms.
Image 1 is the approved identity master. Image 2 is the eight-pose storyboard; use its poses 1–4 as guidance, but keep the solid frosted silver-blue pearl-glass material and silhouette of image 1. No hollow glass shell.
Create exactly 16 complete isolated sprites in a STRICT 4 columns x 4 rows uniform grid, read left-to-right, row by row. A square sheet with square cells. Same camera, same nominal body scale, exactly two small paws, three lower scallops, and two glowing white vertical oval eyes in EVERY cell. Eyes open throughout this part. No pupils, mouth, nose, blush, core, logo, text, grid lines, ground, shadow, props. Actual transparent alpha background. Leave at least 10% empty transparent margin around every pose inside its cell, all parts safely contained. Lighting absolutely stable, upper-left soft highlight, same icy pale blue/lilac color. No labels.
Make a coherent sequence with SMALL gradual differences in silhouette and pose, not 16 unrelated poses:
row 1: neutral front -> tiny lift begins -> body rises while paws lag -> lift continues, lower three waves softly sway.
row 2: rising gradually reaches 3% lift -> paws catch up -> lower waves sway back -> settles at top, still near-front.
row 3: starts small turn toward image-right at 0, 4, 8, 12 degrees -> both eyes remain visible, farther paw gradually recedes but remains visible.
row 4: 15-degree turn -> 18-degree turn -> holds with gently changing paws and waves -> starts returning toward front at about 14 degrees.
Preserve face eye size and spacing by perspective, no jumps or random blinking. Real organic soft-body changes drawn in the sprites; no decorative effects or movement lines. Body center must follow one slow smooth path with only a small vertical lift, never random cell-to-cell repositioning. High-fidelity production game sprite artwork.
```

### part-2

```text
Use case: identity-preserve.
Asset type: true transparent sprite sheet, part 2 of a four-second idle loop, exactly 16 successive drawings for time 2.000 through 3.875 s, each held for 125 ms.
Image 1 is the canonical character identity. Image 2 is part 1 of THIS animation; MATCH EXACTLY its character scale relative to each cell, camera, face size, material density, lighting, color and transparent padding. Continue from its last sprite (bottom-right), which has already returned near front. The future loop ends at the EXACT starting pose of image 2 (top-left); draw the final phases approaching that starting pose very closely.
Output exactly 16 sprites in a strict uniform 4 columns x 4 rows SQUARE grid. Read left to right, row by row, square cells. Full-body character entirely within each cell, same nominal size and anchor as image 2; leave 10% transparent safety margins. Actual alpha transparency, no painted checkerboard, no ground or shadow, no borders, text, marks or labels.
Preserve the frosted dense icy silver-blue pearl-glass ghost, dome head, three lower scallops, two small paw flippers held close to the body (NEVER detached or long dangling arms), and two glowing white oval eyes. No pupils, nose, mouth, cheeks, blush, inner core, logo, props. Upper-left soft highlight stays fixed and gentle, no random light/color shifts. Keep similar solid pearlescent appearance, not hollow transparent shell.
Row 1: continue near-front return; 4 subtle progressive drawings from a nearly front body into a curious 6-degree lean toward image-left. Both little paws stay nestled close, with subtle independent lag and gentle swaying of all three lower scallops. Keep both eyes open.
Row 2: curious lean gently stabilizes. Cell 1 eyes open; cell 2 eyes open; cell 3 BOTH eyes closed as two short white soft arcs for a SINGLE short blink; cell 4 both eyes fully open again and body begins returning upright. Only ONE closed-eye sprite in the entire sheet.
Row 3: upright front; body gradually compresses softly by about 5% in height, 3% wider, paws follow and three lower waves curl slightly upward; gradual squash then begins to release, open eyes.
Row 4: gradual soft spring release and settling, approaching the precise starting sprite in image 2 top-left: centered front, same height, width, eye positions, paws, lower waves and lighting. Final cell visually as close as possible to that starting sprite, NOT an exaggerated extra pose. Tiny genuine drawn organic shape changes, no fixed sprite transformed across cells. High-fidelity game sprite artwork.
```

