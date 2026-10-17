#!/usr/bin/env python3
"""Package sequential, genuine Astral greeting drawings; never draw or interpolate."""
import argparse
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / 'design/mascot/astral-v2/animations/launch-greeting'
SIZE, FPS, TARGET = 384, 24, 96


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def png_bytes(image):
    out = io.BytesIO()
    image.save(out, format='PNG')
    return out.getvalue()


def encode_json(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def bounds(frame):
    return frame.getchannel('A').point(lambda v: 255 if v >= 32 else 0).getbbox()


def edge_alpha(image):
    a, (w, h) = image.getchannel('A'), image.size
    return max(a.crop(box).getextrema()[1] for box in
               ((0, 0, w, 1), (0, h - 1, w, h), (0, 0, 1, h), (w - 1, 0, w, h)))


def validate_frame(frame, label):
    a = frame.getchannel('A')
    require(bounds(frame) is not None, f'{label}: empty drawing / incomplete sheet')
    require(a.getextrema()[0] == 0, f'{label}: no truly transparent pixels')
    require(sum(a.histogram()[1:255]) > 0, f'{label}: no soft alpha')
    require(edge_alpha(frame) < 32, f'{label}: visible alpha32 clipping at cell border')


def grid_splits(sheet, axis):
    """Find a visually transparent corridor; retain all original low-alpha pixels."""
    a = sheet.getchannel('A')
    length = sheet.size[axis]
    cuts = [0]
    for divider in (1, 2, 3):
        nominal, radius = round(divider * length / 4), max(4, min(40, length // 32))
        empty = []
        for pos in range(max(1, nominal - radius), min(length - 1, nominal + radius) + 1):
            box = (pos, 0, pos + 1, sheet.height) if axis == 0 else (0, pos, sheet.width, pos + 1)
            if a.crop(box).getextrema()[1] < 8:
                empty.append(pos)
        candidates = [p for p in empty if p + 1 in empty or p - 1 in empty]
        require(bool(candidates), f'axis {axis}, divider {divider}: no 2px transparent corridor (alpha<8)')
        chosen = min(candidates, key=lambda p: abs(p - nominal))
        cuts.append(chosen)
    return cuts + [length]


def reconstruct(source, record, extent):
    cell = Image.new('RGBA', (extent, extent))
    cell.paste(source.crop(record['sourceCrop']), tuple(record['cellOffset']))
    frame = cell.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return translate_frame(frame, record.get('translationPx', [0, 0]))


def translate_frame(frame, offset):
    """Move the complete raster by integer pixels, rejecting visible clipping."""
    dx, dy = offset
    require(isinstance(dx, int) and isinstance(dy, int), 'Translation must use integer pixels')
    b = bounds(frame)
    require(0 <= b[0] + dx and b[2] + dx <= SIZE and 0 <= b[1] + dy and b[3] + dy <= SIZE,
            f'Placement alignment would clip visible alpha32 pixels: {b}, offset {offset}')
    result = Image.new('RGBA', (SIZE, SIZE))
    result.paste(frame, tuple(offset))
    return result


def upper_dome_anchor(frame):
    """Average upper-dome row-span centers, avoiding the cheek-height moving paw."""
    b = bounds(frame)
    height = b[3] - b[1]
    first, stop = b[1] + math.ceil(height * .15), b[1] + math.ceil(height * .30)
    mask = frame.getchannel('A').point(lambda v: 255 if v >= 32 else 0)
    centers = []
    for y in range(first, stop):
        span = mask.crop((0, y, SIZE, y + 1)).getbbox()
        require(span is not None, f'Empty upper-dome row {y}; placement requires source review')
        centers.append((span[0] + span[2]) / 2)
    require(bool(centers), 'Upper-dome sampling band is empty')
    return [sum(centers) / len(centers), (b[1] + b[3]) / 2], [first, stop]


def transitions(frames):
    geometry, pairs = [], []
    for frame in frames:
        b, a = bounds(frame), frame.getchannel('A')
        mass = sx = sy = 0
        for i, value in enumerate(a.get_flattened_data()):
            mass += value
            sx += (i % SIZE) * value
            sy += (i // SIZE) * value
        geometry.append({'boundsAlpha32': list(b), 'width': b[2] - b[0], 'height': b[3] - b[1],
                         'centroidAlphaPx': [sx / mass, sy / mass]})
    for i in range(len(frames) - 1):
        left, right = geometry[i:i + 2]
        a, b = (f.getchannel('A').point(lambda v: 255 if v >= 32 else 0) for f in frames[i:i + 2])
        intersection = ImageChops.darker(a, b).histogram()[255]
        union = ImageChops.lighter(a, b).histogram()[255]
        pairs.append({'from': i, 'to': i + 1,
                      'widthChangePct': abs(right['width'] - left['width']) / left['width'] * 100,
                      'heightChangePct': abs(right['height'] - left['height']) / left['height'] * 100,
                      'centroidDistancePx': math.dist(left['centroidAlphaPx'], right['centroidAlphaPx']),
                      'silhouetteIoUAlpha32': intersection / union})
    return {'alphaThreshold': 32, 'includesLoopSeam': False, 'measurements': geometry,
            'allAdjacentPairs': pairs,
            'maxWidthChangePct': max(p['widthChangePct'] for p in pairs),
            'maxHeightChangePct': max(p['heightChangePct'] for p in pairs),
            'maxCentroidDistancePx': max(p['centroidDistancePx'] for p in pairs),
            'minSilhouetteIoUAlpha32': min(p['silhouetteIoUAlpha32'] for p in pairs)}


def generation_files(directory):
    """Verify portable archived inputs; original tool-cache output paths are historical."""
    manifest = directory / 'generation.json'
    verified = []
    if not manifest.exists():
        return verified

    def visit(node, location):
        if isinstance(node, list):
            for i, child in enumerate(node):
                visit(child, f'{location}[{i}]')
        elif isinstance(node, dict):
            for path_key, hash_key in (('path', 'sha256'), ('prompt_path', 'prompt_sha256')):
                if path_key not in node:
                    continue
                path = ROOT / node[path_key]
                require(path.is_file(), f'generation {location}: missing archived file {path}')
                actual = digest(path.read_bytes())
                require(actual == node.get(hash_key), f'generation {location}: SHA mismatch for {path}')
                if path_key == 'prompt_path':
                    text = node.get('prompt_text', node.get('text'))
                    if isinstance(text, str):
                        require(path.read_text() == text, f'generation {location}: exact prompt text mismatch')
                verified.append({'record': location, 'path': node[path_key], 'sha256': actual})
            for key, child in node.items():
                visit(child, f'{location}.{key}')
    visit(json.loads(manifest.read_text()), 'generation')
    return verified


def prepare(directory):
    paths = [directory / f'part-{n}-generated.png' for n in range(1, 7)]
    present = [p for p in paths if p.is_file()]
    require(bool(present), f'No source sheets: expected {paths[0]} (strict 4×4 / 16 real drawings)')
    require(present == paths[:len(present)], 'Source sheets must be sequential from part-1; gap found')
    sources, crops = [], []
    for path in present:
        with Image.open(path) as image:
            require(image.mode == 'RGBA', f'{path.name}: expected original RGBA source')
            sheet = image.copy()
        xs, ys = grid_splits(sheet, 0), grid_splits(sheet, 1)
        sources.append({'file': path.name, 'sourceSHA': digest(path.read_bytes()), 'sizePx': list(sheet.size),
                        'gridSplitsX': xs, 'gridSplitsY': ys})
        for row in range(4):
            for col in range(4):
                box = [xs[col], ys[row], xs[col + 1], ys[row + 1]]
                validate_frame(sheet.crop(box), f'{path.name} row {row + 1}, column {col + 1}')
                crops.append((sheet, sources[-1], box))
    extent = max(max(b[2] - b[0], b[3] - b[1]) for _, _, b in crops)
    frames, records, source_placements = [], [], []
    for i, (sheet, source, box) in enumerate(crops):
        record = {'id': i, 'file': f'frames/frame-{i:03d}.png', 'source': source['file'],
                  'sourceSHA': source['sourceSHA'], 'sourceCrop': box,
                  'sourceBoundsAlpha32': list(bounds(sheet.crop(box))),
                  'cellOffset': [(extent - (box[2] - box[0])) // 2, (extent - (box[3] - box[1])) // 2],
                  'uniformScale': SIZE / extent, 'atlasRect': [i % 4 * SIZE, i // 4 * SIZE, SIZE, SIZE]}
        frame = reconstruct(sheet, record, extent)
        source_placements.append(frame)
        b = bounds(frame)
        anchor = [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]
        record.update({'preAlignmentBounds': list(b), 'anchorKind': 'alpha32-bounds-center-entry',
                       'placementBandRows': None})
        if i < 16:
            y = (186 + 8 * (.5 - .5 * math.cos(math.pi * i / 7)) if i <= 7 else
                 194 - 2 * (.5 - .5 * math.cos(math.pi * (i - 7) / 8)))
            record['targetAnchorPx'] = [192, y]
        else:
            anchor, band = upper_dome_anchor(frame)
            record.update({'targetAnchorPx': [192, 192], 'placementBandRows': band,
                           'anchorKind': 'alpha32-upper-dome-mean-row-span-x/full-bounds-center-y'})
        record['placementAnchorPx'] = anchor
        record['translationPx'] = [round(target - source) for target, source in zip(record['targetAnchorPx'], anchor)]
        record['operations'] = [
            {'op': 'crop', 'rect': box},
            {'op': 'pad', 'sizePx': [extent, extent], 'offsetPx': record['cellOffset'], 'fillRGBA': [0, 0, 0, 0]},
            {'op': 'resize', 'sizePx': [SIZE, SIZE], 'filter': 'LANCZOS', 'uniformScale': SIZE / extent},
            {'op': 'translate', 'offsetPx': record['translationPx'], 'sizePx': [SIZE, SIZE], 'fillRGBA': [0, 0, 0, 0]}]
        frame = translate_frame(frame, record['translationPx'])
        validate_frame(frame, record['file'])
        record.update({'frameSHA': digest(png_bytes(frame)), 'rgbaSHA': digest(frame.tobytes()),
                       'boundsAlpha32': list(bounds(frame)), 'alphaRange': list(frame.getchannel('A').getextrema()),
                       'edgeMaxAlpha': edge_alpha(frame)})
        records.append(record)
        frames.append(frame)
    require(len({digest(f.tobytes()) for f in source_placements}) == len(records),
            'Repeated source drawing bytes detected before alignment')
    require(len({r['rgbaSHA'] for r in records}) == len(records), 'Repeated drawing bytes detected')
    atlas = Image.new('RGBA', (SIZE * 4, SIZE * math.ceil(len(frames) / 4)))
    for record, frame in zip(records, frames):
        atlas.paste(frame, tuple(record['atlasRect'][:2]))
    n = len(frames)
    metadata = {'schema': 1, 'name': 'Astral — приветствие', 'status': 'draft-complete' if n == TARGET else 'partial',
                'artisticApproval': False, 'runtimeIntegrated': False, 'silent': True, 'playCount': 1,
                'uniqueDrawings': n, 'targetUniqueDrawings': TARGET, 'targetDurationMs': 4000,
                'displayFps': FPS, 'displayTicks': n, 'ticks': list(range(n)), 'holdTicksPerDrawing': 1,
                'availableDurationMs': n * 1000 / FPS, 'interpolatedDrawings': 0, 'loop': False,
                'frameSizePx': [SIZE, SIZE], 'cellExtent': extent, 'corridorAlphaThresholdExclusive': 8,
                'normalizationPolicy': 'Transparent grid corridors; centered cell padding; one common uniform resize. Frames 0–15: integer translation aligns alpha32 bounds centers to the entry trajectory. Frames 16–95: integer translation aligns upper-dome row-span mean X and full-bounds center Y to [192,192]. No deformation, per-frame scaling, rotation, crossfade, alpha cleanup or repeated start.',
                'entryAlignment': {'framesInclusive': [0, 15], 'anchorKind': 'alpha32 bounding-box center',
                                   'translationRounding': 'nearest integer, ties to even',
                                   'targetX': 192, 'targetYFrames0to7': '186+8*(0.5-0.5*cos(pi*i/7))',
                                   'targetYFrames8to15': '194-2*(0.5-0.5*cos(pi*(i-7)/8))'},
                'greetingAlignment': {'framesInclusive': [16, 95], 'targetAnchorPx': [192, 192],
                                      'alphaThreshold': 32, 'upperDomeBandHeightFractions': [.15, .30],
                                      'rowRange': 'ceil(top+height*0.15) inclusive to ceil(top+height*0.30) exclusive',
                                      'xAnchor': 'mean of (left+rightExclusive)/2 for visible alpha32 row spans',
                                      'yAnchor': 'full alpha32 bounds center', 'translationRounding': 'nearest integer, ties to even'},
                'atlas': 'atlas.png', 'atlasSizePx': list(atlas.size), 'atlasSHA': digest(png_bytes(atlas)),
                'sources': sources, 'frames': records, 'sourcePlacementMetrics': transitions(source_placements),
                'adjacentMetrics': transitions(frames),
                'generationSHA': digest((directory / 'generation.json').read_bytes()) if (directory / 'generation.json').exists() else None,
                'previews': {'webp': 'preview.webp', 'gif': 'preview-light.gif'}}
    return metadata, frames, atlas


def player_html(directory, metadata):
    template = (directory / 'player-template.html').read_text()
    require(template.count('__GREETING_METADATA__') == 1, 'Player template must have one metadata placeholder')
    return template.replace('__GREETING_METADATA__', json.dumps(metadata, ensure_ascii=False).replace('</', '<\\/'))


def durations(count, quantum):
    return [round((i + 1) * 1000 / FPS / quantum) * quantum - round(i * 1000 / FPS / quantum) * quantum
            for i in range(count)]


def check(directory, prepared=None):
    provenance = generation_files(directory)
    metadata, originals, expected_atlas = prepared or prepare(directory)
    require(json.loads((directory / 'atlas.json').read_text()) == metadata, 'Metadata / source provenance mismatch')
    require((directory / 'atlas.png').read_bytes() == png_bytes(expected_atlas), 'Atlas PNG checksum mismatch')
    atlas = Image.open(directory / 'atlas.png').convert('RGBA')
    require(sorted(p.name for p in (directory / 'frames').glob('*.png')) ==
            [Path(r['file']).name for r in metadata['frames']], 'Missing or stale frame PNGs')
    for record, original in zip(metadata['frames'], originals):
        raw = (directory / record['file']).read_bytes()
        require(raw == png_bytes(original), f"{record['file']}: source→PNG byte reconstruction failed")
        frame = Image.open(io.BytesIO(raw)).convert('RGBA')
        validate_frame(frame, record['file'])
        x, y, w, h = record['atlasRect']
        require(atlas.crop((x, y, x + w, y + h)).tobytes() == frame.tobytes(), 'PNG→atlas RGBA mismatch')
    require((directory / 'index.html').read_text() == player_html(directory, metadata), 'Standalone HTML is stale')
    previews, count = {}, len(originals)
    for name, quantum in (('preview.webp', 1), ('preview-light.gif', 10)):
        with Image.open(directory / name) as image:
            require(image.n_frames == count, f'{name}: encoded frame count mismatch')
            require(image.info.get('loop', 1) == 1 if name.endswith('webp') else 'loop' not in image.info,
                    f'{name}: must play once')
            actual = []
            for i in range(image.n_frames):
                image.seek(i)
                image.load()
                actual.append(image.info.get('duration', 0))
                require(image.size == (SIZE, SIZE), f'{name}: unexpected dimensions')
                if name.endswith('webp'):
                    decoded = image.convert('RGBA')
                    validate_frame(decoded, f'{name} frame {i}')
                    # WebP may canonicalize invisible RGB; visible RGBA must remain lossless.
                    require(decoded.getchannel('A').tobytes() == originals[i].getchannel('A').tobytes(),
                            f'{name}: alpha pixels changed')
                    for color in ('black', 'white'):
                        background = Image.new('RGBA', decoded.size, color)
                        left = Image.alpha_composite(background, decoded).convert('RGB')
                        right = Image.alpha_composite(background, originals[i]).convert('RGB')
                        require(ImageChops.difference(left, right).getbbox() is None,
                                f'{name}: visible RGB pixels changed on {color}')
            require(actual == durations(count, quantum), f'{name}: frame timing mismatch {actual}')
            require(abs(sum(actual) - metadata['availableDurationMs']) <= quantum / 2 + 1e-8,
                    f'{name}: total duration mismatch')
            previews[name] = {'frames': image.n_frames, 'durationMs': sum(actual),
                              'timingQuantumMs': quantum, 'playCount': 1, 'sha256': digest((directory / name).read_bytes())}
    result = {'status': metadata['status'], 'checks': 'passed', 'artisticApproval': False, 'runtimeIntegrated': False,
            'uniqueDrawings': count, 'targetUniqueDrawings': TARGET, 'displayFps': FPS,
            'availableDurationMs': metadata['availableDurationMs'], 'targetDurationMs': 4000,
            'sourceToPngBytes': True, 'pngToAtlasRGBA': True, 'sourceAndArtifactHashes': True,
            'softAlphaFrames': count, 'maxBorderAlpha': max(r['edgeMaxAlpha'] for r in metadata['frames']),
            'loopSeamChecked': False, 'previews': previews,
            'verifiedGenerationFiles': provenance,
            'artifactSHA': {name: digest((directory / name).read_bytes()) for name in
                            ('atlas.png', 'atlas.json', 'index.html', 'player-template.html')}}
    if prepared is None:
        require(json.loads((directory / 'verification.json').read_text()) == result,
                'Verification report / output checksum mismatch')
    return result


def build(directory):
    generation_files(directory)
    prepared = prepare(directory)
    metadata, frames, atlas = prepared
    html = player_html(directory, metadata)
    (directory / 'frames').mkdir(exist_ok=True)
    for record, frame in zip(metadata['frames'], frames):
        (directory / record['file']).write_bytes(png_bytes(frame))
    (directory / 'atlas.png').write_bytes(png_bytes(atlas))
    (directory / 'atlas.json').write_text(encode_json(metadata))
    frames[0].save(directory / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=durations(len(frames), 1), loop=1, lossless=True, exact=True, method=4)
    gifs = []
    for frame in frames:
        bg = Image.new('RGBA', frame.size, '#edf0f5')
        bg.alpha_composite(frame)
        gifs.append(bg.convert('RGB'))
    gifs[0].save(directory / 'preview-light.gif', save_all=True, append_images=gifs[1:],
                 duration=durations(len(frames), 10), disposal=2, optimize=False)
    (directory / 'index.html').write_text(html)
    result = check(directory, prepared)
    (directory / 'verification.json').write_text(encode_json(result))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Read-only source reconstruction and output verification')
    parser.add_argument('--directory', type=Path, default=DEFAULT, help='Source/output directory; default: launch-greeting')
    args = parser.parse_args()
    try:
        print(encode_json(check(args.directory) if args.check else build(args.directory)), end='')
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f'Astral greeting: {error}\n')
