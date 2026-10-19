#!/usr/bin/env python3
"""Describe immutable PNG layers and their fixed shoulder; never paint or warp art."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'design/mascot/astral-v2/animations/launch-greeting/wave-layered-probe'
spec = importlib.util.spec_from_file_location('greeting_pack', ROOT / 'scripts/pack-astral-greeting.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


def prepare():
    result = {'schema':1, 'sourceSpriteCount':2, 'generatedFullPoseFrames':0,
              'renderMode':'two immutable PNG layers; continuous rigid paw rotation at a fixed shoulder',
              'durationMs':4000, 'waveCount':3, 'loop':False, 'silent':True,
              'blinkImplemented':False, 'runtimeIntegrated':False, 'artisticApproval':False}
    images = {}
    for kind in ('body','paw'):
        relative = f'assets/{kind}-generated.png'
        path = DIRECTORY / relative
        with Image.open(path) as im:
            assert im.mode == 'RGBA', f'{kind}: expected RGBA'
            a = im.getchannel('A'); assert a.getextrema() == (0,255)
            crop = a.point(lambda v:255 if v >= 8 else 0).getbbox()
            assert crop and sum(a.histogram()[1:255]) > 0
            images[kind] = im.copy()
            result[kind] = {'file':relative, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                            'sizePx':list(im.size), 'crop':list(crop)}
    b = result['body']; left,top,right,bottom = b['crop']; h = bottom-top
    mask = images['body'].getchannel('A').point(lambda v:255 if v >= 32 else 0)
    centers = []
    for y in range(round(top+.15*h),round(top+.25*h)):
        span = mask.crop((0,y,images['body'].width,y+1)).getbbox()
        assert span; centers.append((span[0]+span[2])/2)
    b['headCenterX'] = sum(centers)/len(centers)
    shoulder_y = round(top+.58*h)
    span = mask.crop((0,shoulder_y,images['body'].width,shoulder_y+1)).getbbox()
    b['shoulder'] = [span[0]+28,shoulder_y]
    result['paw']['pivot'] = [690,1095]
    assert images['body'].getchannel('A').getpixel(tuple(b['shoulder'])) >= 128
    assert images['paw'].getchannel('A').getpixel((690,1095)) >= 128
    return result


def check(expected=None):
    expected = expected or prepare()
    assert json.loads((DIRECTORY/'rig.json').read_text()) == expected, 'Rig/source mismatch'
    verified = pack.generation_files(DIRECTORY/'assets')
    assert verified, 'Missing generation provenance'
    return {'checks':'passed','sourceSpriteCount':2,'durationMs':4000,'waveCount':3,
            'provenanceRecords':len(verified),'rawSourceHashes':True,'artisticApproval':False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if args.check:
        print(json.dumps(check(),indent=2));return
    data=prepare();(DIRECTORY/'rig.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    result=check(data);(DIRECTORY/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
