// Makes TrainingTests/Fixtures/gift-expected.json by running app.js's own gift import code on gift-payload.json:
//   node ios-native/dev/gift-fixtures.js app.js "$(cat ios-native/TrainingTests/Fixtures/gift-payload.json)" > ios-native/TrainingTests/Fixtures/gift-expected.json
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const grab = (start) => { const i = src.indexOf(start); if (i < 0) throw start; let j = src.indexOf('\n', i); 
  if (start.startsWith('function')) { let depth = 0, k = src.indexOf('{', i); for (; k < src.length; k++) { if (src[k] === '{') depth++; else if (src[k] === '}') { depth--; if (!depth) break; } } return src.slice(i, k + 1); }
  return src.slice(i, j); };
const parts = ['const TRACK_A', 'const TRACK_B', 'const MUSCLES', 'const EQUIP', 'const GIFT_MAX', 'const str =', 'const TRACK_OK', 'function importExercise', 'const uniqueName', 'function importWorkout', 'function importPlan', 'const cleanCode', 'const fmtCode', 'const pairId', 'function ytId'];
let n = 0;
const code = `let data = {exercises: [{id:'e1', name:'Bench Press', lib:''}, {id:'e2', name:'Squat', lib:'b:backsquat'}], workouts:[{id:'w0', name:'Push'}], plans:[{id:'p0',name:'PPL'}]};
const uid = () => 'id' + (++n); const normName = s => String(s||'').toLowerCase().replace(/[^a-z0-9]/g,''); const libById = id => ['b:benchpress','b:backsquat','b:deadlift'].includes(id) ? {id} : null;
const plural = (n, w) => n + ' ' + w + (n === 1 ? '' : 's');
` + parts.map(grab).join('\n') + `
const payload = JSON.parse(process.argv[3]);
const wid = importWorkout(payload.workout, 'Anna');
const pid = importPlan(payload.plan, 'Anna');
console.log(JSON.stringify({data, codes: payload.codes.map(c => [cleanCode(c), fmtCode(cleanCode(c))]), pair: pairId('zed', 'amy')}));`;
eval(code);
