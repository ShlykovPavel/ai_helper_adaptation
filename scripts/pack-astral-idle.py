#!/usr/bin/env python3
"""Slice generated sprite grids and package a review-only animation; no pose drawing."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'design/mascot/astral-v2/animations/are-you-still-here'
SIZE = 384


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grid_splits(sheet, axis):
    """Locate the transparent gutter near each expected grid boundary."""
    a = sheet.getchannel('A')
    length = sheet.width if axis == 0 else sheet.height
    result = [0]
    for divider in (1, 2, 3):
        nominal = round(divider * length / 4)
        empty = []
        for k in range(nominal - 40, nominal + 41):
            line = a.crop((k, 0, k + 1, sheet.height) if axis == 0
                          else (0, k, sheet.width, k + 1))
            if sum(line.histogram()[32:]) == 0:
                empty.append(k)
        assert empty, (axis, divider, 'no safe grid gutter')
        result.append(empty[len(empty) // 2])
    return result + [length]


def build():
    (DEST / 'frames').mkdir(exist_ok=True)
    frames, records, sources = [], [], []
    for part in (1, 2):
        source = DEST / f'part-{part}-generated.png'
        sheet = Image.open(source).convert('RGBA')
        xs, ys = grid_splits(sheet, 0), grid_splits(sheet, 1)
        sources.append({'file': source.name, 'size': list(sheet.size), 'sha256': sha(source)})
        for row in range(4):
            for col in range(4):
                # Transparent gutter boundaries prevent clipping and neighbouring
                # sprite leakage. Pasting retains original nominal grid anchors.
                extent = round(sheet.width / 4) + 36
                left = round((col + .5) * sheet.width / 4 - extent / 2)
                top = round((row + .5) * sheet.height / 4 - extent / 2)
                box = (xs[col], ys[row], xs[col + 1], ys[row + 1])
                frame = Image.new('RGBA', (extent, extent))
                frame.paste(sheet.crop(box), (box[0] - left, box[1] - top))
                # Only uniform resampling of the whole square cell, never body deformation.
                assert abs(frame.width - frame.height) <= 1, (source, box)
                frame = frame.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
                idx = len(frames)
                # Remove grid layout drift by translation only. Keep genuine body
                # dimensions, paws, eyelids and squash from the generated artwork.
                bounds = frame.getchannel('A').point(lambda v: 255 if v >= 32 else 0).getbbox()
                lift = [0, 1, 2, 4, 6, 8, 9, 10, 10, 9, 8, 6, 4, 2, 1, 0][idx] if idx < 16 else 0
                anchor = (SIZE / 2, SIZE / 2 - lift)
                offset = (round(anchor[0] - (bounds[0] + bounds[2]) / 2),
                          round(anchor[1] - (bounds[1] + bounds[3]) / 2))
                aligned = Image.new('RGBA', frame.size)
                aligned.paste(frame, offset)
                frame = aligned
                name = f'frames/frame-{idx:03d}.png'
                frame.save(DEST / name)
                alpha = frame.getchannel('A')
                solid = alpha.point(lambda v: 255 if v >= 32 else 0)
                edge = max(max(alpha.crop(b).getextrema()) for b in
                           ((0, 0, SIZE, 1), (0, SIZE - 1, SIZE, SIZE),
                            (0, 0, 1, SIZE), (SIZE - 1, 0, SIZE, SIZE)))
                records.append({'id': idx, 'file': name, 'sha256': sha(DEST / name),
                                'source': source.name, 'sourceCrop': list(box),
                                'normalization': {'uniformCellSizePx': [SIZE, SIZE],
                                                  'sourceVirtualCell': [left, top, extent, extent],
                                                  'translationPx': list(offset), 'targetAnchorPx': list(anchor)},
                                'atlasRect': [(idx % 4) * SIZE, (idx // 4) * SIZE, SIZE, SIZE],
                                'alphaRange': list(alpha.getextrema()),
                                'visibleBoundsAlpha32': list(solid.getbbox()),
                                'edgeMaxAlpha': edge})
                frames.append(frame)
    atlas = Image.new('RGBA', (SIZE * 4, SIZE * 8))
    for rec, frame in zip(records, frames):
        atlas.paste(frame, tuple(rec['atlasRect'][:2]))
    atlas.save(DEST / 'atlas.png')
    # 32 source drawings, 96 display ticks. The last tick reuses frame 0 for an exact end pose.
    ticks = [i for i in range(32) for _ in range(3)]
    ticks[-1] = 0
    metadata = {'schema': 1, 'name': 'Ты ещё тут?', 'status': 'draft-review-only',
                'runtimeIntegrated': False, 'atlas': 'atlas.png', 'frameSizePx': [SIZE, SIZE],
                'atlasSizePx': list(atlas.size), 'uniqueDrawings': 32,
                'displayFps': 24, 'displayTicks': 96, 'durationMs': 4000,
                'nominalNewDrawingsPerSecond': 8, 'timelineDistinctDrawings': len(set(ticks)),
                'interpolatedDrawings': 0, 'ticks': ticks,
                'loopPolicy': 'Last display tick reuses exact frame 0. Near-loop generated poses can still jump.',
                'sources': sources, 'frames': records,
                'preview': {'webp': 'preview.webp', 'webpDurationMs': 4000,
                            'gif': 'preview-light.gif', 'gifDurationMs': 4000}}
    (DEST / 'atlas.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    # Animation file formats use integer milliseconds. Group each run and quantize boundaries.
    runs = []
    for tick, frame_id in enumerate(ticks):
        if not runs or runs[-1][0] != frame_id:
            runs.append([frame_id, tick, tick + 1])
        else:
            runs[-1][2] += 1
    durations = [round(end * 1000 / 24) - round(start * 1000 / 24) for _, start, end in runs]
    webp = [frames[idx] for idx, _, _ in runs]
    webp[0].save(DEST / 'preview.webp', save_all=True, append_images=webp[1:],
                 duration=durations, loop=0, lossless=True, method=4)
    gifs = []
    for frame in webp:
        bg = Image.new('RGBA', frame.size, '#edf0f5')
        bg.alpha_composite(frame)
        gifs.append(bg.convert('RGB'))
    gif_ms = [round(end * 100 / 24) * 10 - round(start * 100 / 24) * 10
              for _, start, end in runs]
    gifs[0].save(DEST / 'preview-light.gif', save_all=True, append_images=gifs[1:],
                 duration=gif_ms, loop=0, disposal=2)
    template = (DEST / 'player-template.html').read_text()
    (DEST / 'index.html').write_text(template.replace('__METADATA__', json.dumps(metadata, ensure_ascii=False)))
    print(json.dumps(check(), ensure_ascii=False, indent=2))


def check():
    meta = json.loads((DEST / 'atlas.json').read_text())
    frames = [Image.open(DEST / r['file']).convert('RGBA') for r in meta['frames']]
    atlas = Image.open(DEST / meta['atlas']).convert('RGBA')
    assert len(set(r['sha256'] for r in meta['frames'])) == meta['uniqueDrawings'] == 32
    assert len(meta['ticks']) == 96 and meta['ticks'][-1] == meta['ticks'][0] == 0
    assert len(meta['ticks']) / meta['displayFps'] * 1000 == meta['durationMs'] == 4000
    for rec, frame in zip(meta['frames'], frames):
        alpha = frame.getchannel('A')
        assert frame.size == (SIZE, SIZE) and alpha.getextrema()[0] == 0
        edge = max(max(alpha.crop(b).getextrema()) for b in
                   ((0, 0, SIZE, 1), (0, SIZE - 1, SIZE, SIZE),
                    (0, 0, 1, SIZE), (SIZE - 1, 0, SIZE, SIZE)))
        assert edge == rec['edgeMaxAlpha'] < 32, (rec['id'], 'visible border clipping')
        assert list(alpha.getextrema()) == rec['alphaRange']
        bbox = alpha.point(lambda v: 255 if v >= 32 else 0).getbbox()
        assert list(bbox) == rec['visibleBoundsAlpha32']
        anchor = rec['normalization']['targetAnchorPx']
        assert abs((bbox[0] + bbox[2]) / 2 - anchor[0]) <= .5
        assert abs((bbox[1] + bbox[3]) / 2 - anchor[1]) <= .5
        assert sha(DEST / rec['file']) == rec['sha256']
        x, y, w, h = rec['atlasRect']
        assert frame.tobytes() == atlas.crop((x, y, x + w, y + h)).tobytes()
    preview = {}
    for name in ('preview.webp', 'preview-light.gif'):
        im = Image.open(DEST / name)
        duration = 0
        for idx in range(im.n_frames):
            im.seek(idx)
            im.load()
            duration += im.info['duration']
        assert duration == 4000, (name, duration)
        preview[name] = {'encodedFrames': im.n_frames, 'durationMs': duration}
    # Compare meaningful RGBA differences for the generated approach and exact repeated endpoint.
    dif = ImageChops.difference(frames[-1], frames[0])
    result = {'uniqueDrawings': 32, 'displayTicks': 96, 'durationMs': 4000,
              'displayFps': 24, 'nominalNewDrawingsPerSecond': 8,
              'transparentFrames': len(frames), 'timelineDistinctDrawings': len(set(meta['ticks'])),
              'maxBorderAlpha': max(r['edgeMaxAlpha'] for r in meta['frames']),
              'exactRepeatedEndpoint': True, 'generatedEndDiffBounds': dif.getbbox(alpha_only=False),
              'previews': preview}
    (DEST / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        print(json.dumps(check(), ensure_ascii=False, indent=2))
    else:
        build()
