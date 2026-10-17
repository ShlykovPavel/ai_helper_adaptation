#!/usr/bin/env python3
"""Package real generated Astral drawings. No drawing, warping or interpolation."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'design/mascot/astral-v2/animations/are-you-still-here-v2'
V1 = DEST.with_name('are-you-still-here')
SIZE = 384


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name, value):
    (DEST / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def grid_splits(sheet, axis):
    """Find genuine transparent gutters, not nominal equal quarters."""
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


def bounds(frame):
    return frame.getchannel('A').point(lambda v: 255 if v >= 32 else 0).getbbox()


def edge_alpha(frame):
    a = frame.getchannel('A')
    w, h = frame.size
    return max(a.crop(b).getextrema()[1] for b in
               ((0, 0, w, 1), (0, h - 1, w, h), (0, 0, 1, h), (w - 1, 0, w, h)))


def geometry(frame):
    a = frame.getchannel('A')
    b = bounds(frame)
    # Alpha-weighted centroid excludes invisible RGB; unthresholded alpha retains soft edges.
    mass = sx = sy = 0
    for y in range(frame.height):
        for x, value in enumerate(a.crop((0, y, frame.width, y + 1)).get_flattened_data()):
            mass += value
            sx += x * value
            sy += y * value
    return {'boundsAlpha32': list(b), 'width': b[2] - b[0], 'height': b[3] - b[1],
            'centroidAlphaPx': [sx / mass, sy / mass]}


def transitions(frames):
    measures = [geometry(frame) for frame in frames]
    pairs = []
    for i, left in enumerate(measures):
        j = (i + 1) % len(frames)
        right = measures[j]
        a, b = frames[i].getchannel('A'), frames[j].getchannel('A')
        am = a.point(lambda v: 255 if v >= 32 else 0)
        bm = b.point(lambda v: 255 if v >= 32 else 0)
        intersection = sum(ImageChops.darker(am, bm).histogram()[255:])
        union = sum(ImageChops.lighter(am, bm).histogram()[255:])
        pairs.append({'from': i, 'to': j,
                      'widthPx': [left['width'], right['width']],
                      'heightPx': [left['height'], right['height']],
                      'widthChangePct': abs(right['width'] - left['width']) / left['width'] * 100,
                      'heightChangePct': abs(right['height'] - left['height']) / left['height'] * 100,
                      'centroidDistancePx': math.dist(left['centroidAlphaPx'], right['centroidAlphaPx']),
                      'silhouetteIoUAlpha32': intersection / union})
    return {'alphaThreshold': 32, 'percentageDenominator': 'preceding drawing dimension',
            'includesLoopSeamInMaxima': True, 'seam': pairs[-1],
            'maxAdjacentWidth': max(pairs, key=lambda p: p['widthChangePct']),
            'maxAdjacentHeight': max(pairs, key=lambda p: p['heightChangePct']),
            'maxAdjacentCentroid': max(pairs, key=lambda p: p['centroidDistancePx']),
            'minAdjacentSilhouetteIoU': min(pairs, key=lambda p: p['silhouetteIoUAlpha32']),
            'measurements': measures, 'allAdjacentPairs': pairs}


def reconstruct(record):
    source = Image.open(DEST / record['source']).convert('RGBA')
    n = record['normalization']
    left, top, extent, _ = n['sourceVirtualCell']
    b = record['sourceCrop']
    cell = Image.new('RGBA', (extent, extent))
    cell.paste(source.crop(b), (b[0] - left, b[1] - top))
    cell = cell.resize(tuple(n['resizePx']), Image.Resampling.LANCZOS)
    result = Image.new('RGBA', (SIZE, SIZE))
    result.paste(cell, tuple(n['translationPx']))
    return result


def build():
    (DEST / 'frames').mkdir(exist_ok=True)
    frames, records, sources = [], [], []
    for part in (1, 2, 3):
        source = DEST / f'part-{part}-generated.png'
        sheet = Image.open(source).convert('RGBA')
        xs, ys = grid_splits(sheet, 0), grid_splits(sheet, 1)
        assert sheet.width == sheet.height
        sources.append({'file': source.name, 'size': list(sheet.size), 'sha256': sha(source),
                        'gridSplitsX': xs, 'gridSplitsY': ys})
        for row in range(4):
            for col in range(4):
                extent = round(sheet.width / 4) + 36
                left = round((col + .5) * sheet.width / 4 - extent / 2)
                top = round((row + .5) * sheet.height / 4 - extent / 2)
                box = (xs[col], ys[row], xs[col + 1], ys[row + 1])
                cell = Image.new('RGBA', (extent, extent))
                cell.paste(sheet.crop(box), (box[0] - left, box[1] - top))
                cell = cell.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
                idx = len(frames)
                # One smooth, small float. No per-pose scaling or silhouette repair.
                lift = 8 * math.sin(math.pi * idx / 32) ** 2 if idx <= 32 else 0
                anchor = [SIZE / 2, SIZE / 2 - lift]
                b = bounds(cell)
                offset = [round(anchor[0] - (b[0] + b[2]) / 2),
                          round(anchor[1] - (b[1] + b[3]) / 2)]
                frame = Image.new('RGBA', (SIZE, SIZE))
                frame.paste(cell, tuple(offset))
                name = f'frames/frame-{idx:03d}.png'
                frame.save(DEST / name)
                records.append({'id': idx, 'file': name, 'sha256': sha(DEST / name),
                                'source': source.name, 'sourceCrop': list(box),
                                'normalization': {'sourceVirtualCell': [left, top, extent, extent],
                                                  'resizePx': [SIZE, SIZE],
                                                  'uniformScale': SIZE / extent,
                                                  'translationPx': offset, 'targetAnchorPx': anchor},
                                'atlasRect': [(idx % 4) * SIZE, (idx // 4) * SIZE, SIZE, SIZE],
                                'alphaRange': list(frame.getchannel('A').getextrema()),
                                'visibleBoundsAlpha32': list(bounds(frame)),
                                'edgeMaxAlpha': edge_alpha(frame)})
                frames.append(frame)
    atlas = Image.new('RGBA', (SIZE * 4, SIZE * 12))
    for rec, frame in zip(records, frames):
        atlas.paste(frame, tuple(rec['atlasRect'][:2]))
    atlas.save(DEST / 'atlas.png')
    ticks = [i for i in range(48) for _ in range(2)]
    metadata = {'schema': 2, 'name': 'Ты ещё тут? — v2', 'status': 'draft-review-only',
                'runtimeIntegrated': False, 'atlas': 'atlas.png', 'frameSizePx': [SIZE, SIZE],
                'atlasSizePx': list(atlas.size), 'uniqueDrawings': 48,
                'displayFps': 24, 'displayTicks': 96, 'durationMs': 4000,
                'nominalNewDrawingsPerSecond': 12, 'timelineDistinctDrawings': 48,
                'interpolatedDrawings': 0, 'ticks': ticks,
                'loopPolicy': 'All 48 genuine drawings held exactly 2 ticks. No repeated start inserted; seam is 47→0.',
                'normalizationPolicy': 'Gutter slicing, same uniform cell resize, whole-drawing translation on smooth float path; no deformation, crossfade or interpolation.',
                'sources': sources, 'frames': records,
                'selectedThirdSheetCandidate': next((p.name for p in sorted(DEST.glob('part-3-candidate-*.png')) if sha(p) == sources[-1]['sha256']), None),
                'preview': {'webp': 'preview.webp', 'gif': 'preview-light.gif'}}
    write_json('atlas.json', metadata)
    durations = [round((i + 1) * 4000 / 48) - round(i * 4000 / 48) for i in range(48)]
    frames[0].save(DEST / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, lossless=True, method=4)
    gifs = []
    for frame in frames:
        bg = Image.new('RGBA', frame.size, '#edf0f5')
        bg.alpha_composite(frame)
        gifs.append(bg.convert('RGB'))
    gif_ms = [round((i + 1) * 400 / 48) * 10 - round(i * 400 / 48) * 10 for i in range(48)]
    gifs[0].save(DEST / 'preview-light.gif', save_all=True, append_images=gifs[1:],
                 duration=gif_ms, loop=0, disposal=2)
    v1_meta = json.loads((V1 / 'atlas.json').read_text())
    template = (DEST / 'player-template.html').read_text()
    (DEST / 'index.html').write_text(template.replace('__V2_METADATA__', json.dumps(metadata, ensure_ascii=False))
                                   .replace('__V1_METADATA__', json.dumps(v1_meta, ensure_ascii=False)))
    generation()
    print(json.dumps(check(), ensure_ascii=False, indent=2))


def generation():
    master = ROOT / 'design/mascot/astral-v2/astral-idle-master.png'
    refs = [master, DEST / 'loop-start-reference.png', DEST / 'part-2-generated.png', DEST / 'part-1-generated.png']
    attempts = []
    original = DEST / 'part-3-candidate-original.png'
    if original.exists():
        attempts.append({'file': original.name, 'sha256': sha(original), 'promptFile': 'prompt-part3.txt',
                         'generatedDate': '2026-10-17',
                         'referenceOrder': [{'file': str(p.relative_to(ROOT)), 'sha256': sha(p)} for p in refs],
                         'origin': '/Users/pavel/.codex/generated_images/01a1486f-0d80-7770-a2dd-108c5751408f/exec-f1cbb135-226c-4a6c-941c-2cc83b5b1a0f.png'})
    corrected = DEST / 'part-3-candidate-corrected.png'
    if corrected.exists():
        correction_refs = [original, refs[1], refs[2], master]
        attempts.append({'file': corrected.name, 'sha256': sha(corrected), 'promptFile': 'prompt-part3-correction.txt',
                         'generatedDate': '2026-10-17',
                         'referenceOrder': [{'file': str(p.relative_to(ROOT)), 'sha256': sha(p)} for p in correction_refs],
                         'origin': '/Users/pavel/.codex/generated_images/01a1486f-0d80-7770-a2dd-108c5751408f/exec-a8a98f62-95e9-4275-9435-2da38b8f2fc7.png'})
    write_json('generation.json', {'date': '2026-10-17', 'tool': 'built-in image_gen.imagegen',
              'fallbackCLIUsed': False, 'transparent_background': True,
              'earlierInputsResumedFromDisk': True,
              'referenceOrderEarlierCalls': 'See exact persisted prompts; original call logs not available to resumed packer.',
              'part3Attempts': attempts,
              'selectedPart3Candidate': next((a['file'] for a in attempts if a['sha256'] == sha(DEST / 'part-3-generated.png')), None),
              'selectedPart3Sha256': sha(DEST / 'part-3-generated.png'),
              'selectionReason': 'Original selected: correction reduces local height jump but worsens loop width seam from 8.45% to 12.16%. Neither candidate is seamless.',
              'masterSha256': sha(master),
              'prompts': {p.name: {'text': p.read_text(), 'sha256': sha(p)} for p in sorted(DEST.glob('prompt-*.txt'))},
              'artifacts': [{'file': p.name, 'sha256': sha(p),
                             'generatedDate': '2026-10-17' if p.name == 'part-3-generated.png' else '2026-10-16',
                             'dateEvidence': 'current-session generation' if p.name == 'part-3-generated.png' else 'resumed session chronology confirmed by parent; earlier tool-call origin path unavailable'}
                            for p in sorted(DEST.glob('*-generated.png'))],
              'references': [{'file': p.name, 'sha256': sha(p)} for p in sorted(DEST.glob('*reference.png'))],
              'processing': 'scripts/pack-astral-idle-v2.py; no code-drawn body, deformation, crossfade or interpolated drawing'})


def check():
    meta = json.loads((DEST / 'atlas.json').read_text())
    frames = [Image.open(DEST / r['file']).convert('RGBA') for r in meta['frames']]
    atlas = Image.open(DEST / 'atlas.png').convert('RGBA')
    assert len(frames) == 48 and len({f.tobytes() for f in frames}) == 48
    assert [r['id'] for r in meta['frames']] == list(range(48))
    assert meta['uniqueDrawings'] == meta['timelineDistinctDrawings'] == 48
    assert meta['frameSizePx'] == [SIZE, SIZE]
    assert meta['atlasSizePx'] == list(atlas.size) == [SIZE * 4, SIZE * 12]
    assert meta['displayFps'] == 24 and meta['displayTicks'] == 96
    assert meta['nominalNewDrawingsPerSecond'] == 12 and meta['interpolatedDrawings'] == 0
    assert meta['ticks'] == [i for i in range(48) for _ in range(2)]
    assert len(meta['ticks']) == 96 and meta['ticks'][-1] == 47
    assert len(meta['ticks']) / meta['displayFps'] * 1000 == meta['durationMs'] == 4000
    for source in meta['sources']:
        assert sha(DEST / source['file']) == source['sha256']
    provenance = json.loads((DEST / 'generation.json').read_text())
    actual_third_sha = sha(DEST / 'part-3-generated.png')
    assert provenance['selectedPart3Sha256'] == actual_third_sha
    assert sha(DEST / provenance['selectedPart3Candidate']) == actual_third_sha
    assert meta['selectedThirdSheetCandidate'] == provenance['selectedPart3Candidate']
    for prompt_file, prompt in provenance['prompts'].items():
        assert sha(DEST / prompt_file) == prompt['sha256']
        assert (DEST / prompt_file).read_text() == prompt['text']
    for artifact in provenance['artifacts'] + provenance['references'] + provenance['part3Attempts']:
        assert sha(DEST / artifact['file']) == artifact['sha256']
    for record, frame in zip(meta['frames'], frames):
        assert frame.size == (SIZE, SIZE)
        assert frame.getchannel('A').getextrema()[0] == 0
        assert sum(frame.getchannel('A').histogram()[1:255]) > 0, (record['id'], 'no soft alpha')
        assert list(frame.getchannel('A').getextrema()) == record['alphaRange']
        assert edge_alpha(frame) == record['edgeMaxAlpha'] < 32, (record['id'], 'visible edge clipping')
        assert list(bounds(frame)) == record['visibleBoundsAlpha32']
        assert sha(DEST / record['file']) == record['sha256']
        assert reconstruct(record).tobytes() == frame.tobytes(), (record['id'], 'reconstruction')
        # Prove the virtual cell did not cut opaque parts before resizing.
        source = Image.open(DEST / record['source']).convert('RGBA')
        b = record['sourceCrop']
        crop = source.crop(b)
        left, top, extent, _ = record['normalization']['sourceVirtualCell']
        raw_bounds = bounds(crop)
        assert 0 <= raw_bounds[0] + b[0] - left and raw_bounds[2] + b[0] - left <= extent
        assert 0 <= raw_bounds[1] + b[1] - top and raw_bounds[3] + b[1] - top <= extent
        x, y, w, h = record['atlasRect']
        assert atlas.crop((x, y, x + w, y + h)).tobytes() == frame.tobytes()
    previews = {}
    for name in ('preview.webp', 'preview-light.gif'):
        im = Image.open(DEST / name)
        duration, alpha_min = 0, 255
        for idx in range(im.n_frames):
            im.seek(idx)
            im.load()
            duration += im.info['duration']
            alpha_min = min(alpha_min, im.convert('RGBA').getchannel('A').getextrema()[0])
            if name.endswith('webp'):
                assert im.convert('RGBA').getchannel('A').getextrema()[0] == 0, (name, idx, 'opaque frame')
        assert duration == 4000 and im.n_frames == 48, (name, duration, im.n_frames)
        if name.endswith('webp'):
            assert alpha_min == 0
        previews[name] = {'encodedFrames': im.n_frames, 'durationMs': duration, 'minimumAlpha': alpha_min}
    v1_meta = json.loads((V1 / 'atlas.json').read_text())
    v1_frames = [Image.open(V1 / r['file']).convert('RGBA') for r in v1_meta['frames']]
    metrics = {'v1': transitions(v1_frames), 'v2': transitions(frames)}
    write_json('comparison.json', metrics)
    result = {'status': 'checks-passed-partial-design-result', 'uniqueDrawings': 48,
              'displayTicks': 96, 'durationMs': 4000, 'displayFps': 24,
              'nominalNewDrawingsPerSecond': 12, 'uniformHoldTicks': 2,
              'transparentFrames': 48, 'maxBorderAlpha': max(edge_alpha(f) for f in frames),
              'softAlphaFrames': 48, 'sourceVisibleBoundsUnclippedAlpha32': True,
              'sourceReconstructionRGBA': True, 'atlasPixelsRGBA': True,
              'generationSourceAndPromptHashes': True,
              'insertedRepeatedEndpoint': False,
              'generatedEndDiffBoundsRGBA': ImageChops.difference(frames[-1], frames[0]).getbbox(alpha_only=False),
              'previews': previews,
              'comparison': {v: {k: value for k, value in m.items() if k not in ('measurements', 'allAdjacentPairs')} for v, m in metrics.items()},
              'visualReview': {'staticSheets': 'parent reviewed all sheets; original part3 retained with documented seam and release defects',
                               'browser': 'parent checked pause, seek, light background, 26/64px; clear lean at v2 frame24',
                               'seamlessClaim': False}}
    write_json('verification.json', result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        print(json.dumps(check(), ensure_ascii=False, indent=2))
    else:
        build()
