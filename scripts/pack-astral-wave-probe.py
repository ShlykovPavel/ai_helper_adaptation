#!/usr/bin/env python3
"""Pack the isolated wave study without drawing, warping or interpolating."""
import argparse
import importlib.util
import json
import math
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'design/mascot/astral-v2/animations/launch-greeting/wave-redraw-probe'
spec = importlib.util.spec_from_file_location('greeting_pack', ROOT / 'scripts/pack-astral-greeting.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)
FPS = 12


def prepare():
    path = DIRECTORY / 'wave-source.png'
    with Image.open(path) as image:
        pack.require(image.mode == 'RGBA', 'Expected original RGBA source')
        sheet = image.copy()
    xs, ys = pack.grid_splits(sheet, 0), pack.grid_splits(sheet, 1)
    boxes = [[xs[c], ys[r], xs[c + 1], ys[r + 1]] for r in range(4) for c in range(4)]
    # The newer outward pose extends farther left. Add the same transparent
    # padding to every cell, preserving one shared scale and visible anatomy.
    safe_padding = 0 if DIRECTORY.name == 'wave-redraw-probe' else 16
    extent = max(max(b[2] - b[0], b[3] - b[1]) for b in boxes) + safe_padding
    frames, records = [], []
    for i, box in enumerate(boxes):
        crop = sheet.crop(box)
        pack.validate_frame(crop, f'Original cell {i}')
        record = {'id': i, 'sourceCrop': box,
                  'cellOffset': [(extent - crop.width) // 2, (extent - crop.height) // 2],
                  'uniformScale': pack.SIZE / extent,
                  'file': f'frames/frame-{i:03d}.png',
                  'atlasRect': [i % 4 * pack.SIZE, i // 4 * pack.SIZE, pack.SIZE, pack.SIZE]}
        frame = pack.reconstruct(sheet, record, extent)
        b = pack.bounds(frame)
        mask = frame.getchannel('A').point(lambda v: 255 if v >= 32 else 0)
        band = [b[1] + math.ceil((b[3] - b[1]) * t) for t in (.10, .20)]
        spans = [mask.crop((0, y, pack.SIZE, y + 1)).getbbox() for y in range(*band)]
        pack.require(all(spans), 'Empty upper-head row')
        anchor_x = sum((s[0] + s[2]) / 2 for s in spans) / len(spans)
        record.update({'anchorBandRows': band, 'anchorX': anchor_x, 'sourceTopY': b[1],
                       'translationPx': [round(pack.SIZE / 2 - anchor_x), 40 - b[1]]})
        frame = pack.translate_frame(frame, record['translationPx'])
        pack.validate_frame(frame, record['file'])
        record.update({'rgbaSHA': pack.digest(frame.tobytes()), 'frameSHA': pack.digest(pack.png_bytes(frame)),
                       'boundsAlpha32': list(pack.bounds(frame)), 'edgeMaxAlpha': pack.edge_alpha(frame)})
        records.append(record)
        frames.append(frame)
    pack.require(len({r['rgbaSHA'] for r in records}) == 16, 'Repeated drawings')
    atlas = Image.new('RGBA', (pack.SIZE * 4, pack.SIZE * 4))
    for record, frame in zip(records, frames):
        atlas.paste(frame, tuple(record['atlasRect'][:2]))
    meta = {'schema': 1, 'status': 'motion-study-unapproved', 'uniqueDrawings': 16,
            'displayFps': FPS, 'availableDurationMs': 16 * 1000 / FPS, 'loop': False,
            'artisticApproval': False, 'runtimeIntegrated': False, 'silent': True,
            'frameSizePx': [pack.SIZE, pack.SIZE], 'atlas': 'atlas.png', 'atlasSizePx': list(atlas.size),
            'sourceSHA': pack.digest(path.read_bytes()), 'cellExtent': extent,
            'normalization': 'Transparent corridors, common square padding and uniform resize; integer translation only. Upper-head X (10–20% bbox height) to192, topY to40. No pose edits, per-frame scaling, rotation or interpolation.',
            'generationSHA': pack.digest((DIRECTORY / 'generation.json').read_bytes()),
            'frames': records, 'adjacentMetrics': pack.transitions(frames)}
    if safe_padding:
        meta['commonSafePaddingSourcePx'] = safe_padding
        meta['normalization'] += f' Common cell extent includes {safe_padding}px of extra transparent padding, shared by all16 drawings.'
    return meta, frames, atlas


def html(meta):
    template = (DIRECTORY.parent / 'player-template.html').read_text()
    template = template.replace('Astral · Приветствие', 'Astral · Проба одного взмаха')
    template = template.replace('Тихое «привет»', 'Проба одного взмаха')
    template = template.replace('24 настоящих рисунка/с', '12 настоящих рисунков/с · проба движения')
    template = template.replace('Дизайн-проба; не подключена к приложению.',
                                'Проба нового движения. Оценка жеста ещё открыта; это не полная сценка и не финальные 24 рисунка/с.')
    template = re.sub(r"\$\('status'\)\.textContent=.*?;", "$('status').textContent='16 разных рисунков · 1,333 с · без звука';", template)
    template = re.sub(r"\$\('badge'\)\.textContent=.*?;", "$('badge').textContent='Один взмах · отдельная проба';", template)
    template = re.sub(r'<details open>.*?</details>', '<details><summary>Исходные 16 рисунков</summary><p id="storyboard-note">Исходный лист в порядке слева направо, сверху вниз.</p><img id="storyboard" src="wave-source.png" alt="Исходные рисунки пробы взмаха"></details>', template, flags=re.S)
    template = template.replace('<footer>', '<footer><a href="../index.html">Предыдущий черновик для сравнения</a> · ')
    if DIRECTORY.name != 'wave-redraw-probe':
        template = template.replace('Проба одного взмаха', 'Правка приветственного взмаха')
        template = template.replace('Один взмах · отдельная проба', 'Продолжение пробы B')
        template = template.replace('<footer>', '<footer><a href="../wave-redraw-probe/index.html">Проба B для сравнения</a> · ')
    return template.replace('__GREETING_METADATA__', json.dumps(meta, ensure_ascii=False).replace('</', '<\\/'))


def check(prepared=None):
    meta, frames, atlas = prepared or prepare()
    pack.require(json.loads((DIRECTORY / 'atlas.json').read_text()) == meta, 'Metadata mismatch')
    pack.require((DIRECTORY / 'index.html').read_text() == html(meta), 'Player mismatch')
    for record, frame in zip(meta['frames'], frames):
        pack.require((DIRECTORY / record['file']).read_bytes() == pack.png_bytes(frame), 'PNG reconstruction mismatch')
    with Image.open(DIRECTORY / 'atlas.png') as actual:
        pack.require(actual.mode == 'RGBA' and actual.size == atlas.size and actual.tobytes() == atlas.tobytes(), 'Atlas mismatch')
    provenance = pack.generation_files(DIRECTORY)
    pack.require(bool(provenance), 'Missing provenance')
    return {'checks': 'passed', 'uniqueDrawings': 16, 'displayFps': FPS,
            'durationMs': meta['availableDurationMs'], 'sourceToPng': True, 'pngToAtlas': True,
            'provenanceRecords': len(provenance), 'artisticApproval': False,
            'maxBorderAlpha': max(r['edgeMaxAlpha'] for r in meta['frames'])}


def main():
    global DIRECTORY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DIRECTORY, help='Directory containing wave-source.png and generation.json')
    parser.add_argument('--check', action='store_true', help='Verify without writing files')
    args = parser.parse_args()
    DIRECTORY = args.directory.resolve()
    if args.check:
        print(pack.encode_json(check()))
        return
    meta, frames, atlas = prepare()
    (DIRECTORY / 'frames').mkdir(exist_ok=True)
    for record, frame in zip(meta['frames'], frames):
        (DIRECTORY / record['file']).write_bytes(pack.png_bytes(frame))
    (DIRECTORY / 'atlas.png').write_bytes(pack.png_bytes(atlas))
    (DIRECTORY / 'atlas.json').write_text(pack.encode_json(meta))
    (DIRECTORY / 'index.html').write_text(html(meta))
    result = check((meta, frames, atlas))
    (DIRECTORY / 'verification.json').write_text(pack.encode_json(result))
    print(pack.encode_json(result))


if __name__ == '__main__':
    main()
