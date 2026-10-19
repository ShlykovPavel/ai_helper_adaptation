import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DURATION, poseAt, geometry, paint} from '../design/mascot/astral-v2/animations/launch-greeting/wave-layered-probe/motion.mjs';

const meta = JSON.parse(readFileSync(new URL('../design/mascot/astral-v2/animations/launch-greeting/wave-layered-probe/rig.json', import.meta.url)));
assert.equal(DURATION, 4000);
assert.equal(meta.sourceSpriteCount, 2);
assert.equal(meta.generatedFullPoseFrames, 0);
assert.equal(poseAt(4000).angle, poseAt(500).angle);
assert.equal(poseAt(4000).opacity, 1);
let largestStep = 0, waveMinima = 0;
for (let t=1;t<=4000;t++) {
 const step = poseAt(t).angle-poseAt(t-1).angle;
 largestStep = Math.max(largestStep,Math.abs(step));
 assert.ok(Number.isFinite(poseAt(t).angle));
 if(t>650&&t<=1200) assert.ok(step>=-1e-10,'Lift reverses direction');
 if(t>2500&&t<=3450) assert.ok(step<=1e-10,'Lowering reverses direction');
 if(t>1200&&t<2499 && step<0 && poseAt(t+1).angle-poseAt(t).angle>=0) waveMinima++;
}
assert.ok(largestStep<0.5,`Discontinuous angle: ${largestStep} degrees/ms`);
assert.equal(waveMinima,3,'Expected three outward extremes');

const g = geometry(meta), positions = [];
const bodyImage = {}, pawImage = {};
for(let t=0;t<=4000;t+=10) {
 const calls = [];
 const ctx = {canvas:{width:768,height:768},setTransform(){},clearRect(){},save(){},restore(){},
  translate(...args){calls.push(['joint',...args]);},rotate(angle){calls.push(['angle',angle]);},
  drawImage(image,...args){calls.push([image===bodyImage?'body':'paw',...args]);}};
 paint(ctx,bodyImage,pawImage,meta,t,384,2);
 positions.push(calls.find(c=>c[0]==='joint'));
 const bodyCall=calls.find(c=>c[0]==='body');
 assert.deepEqual(bodyCall,['body',...meta.body.crop.slice(0,2),meta.body.crop[2]-meta.body.crop[0],meta.body.crop[3]-meta.body.crop[1],g.body.x,g.body.y,g.body.width,g.body.height]);
 // Conservative full crop rectangle, including its transparent corners.
 const angle=poseAt(t).angle*Math.PI/180;
 for(const x of [g.paw.x,g.paw.x+g.paw.width]) for(const y of [g.paw.y,g.paw.y+g.paw.height]) {
  const px=g.joint[0]+x*Math.cos(angle)-y*Math.sin(angle), py=g.joint[1]+x*Math.sin(angle)+y*Math.cos(angle);
  assert.ok(px>=0&&px<=384&&py>=0&&py<=384,`Paw clipping at${t}: ${px},${py}`);
 }
}
for(const position of positions) assert.deepEqual(position,positions[0],'Shoulder moved');
console.log(JSON.stringify({checks:'passed',sampledPoses:401,angleSamples:4001,waveCount:waveMinima,
 maximumAngleStepDegreesPerMs:largestStep,bodyDrawUnchanged:true,shoulderFixed:true,pawCropNeverClipped:true,durationMs:4000},null,2));
