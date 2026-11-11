const fs=require('fs'), acorn=require('acorn'), walk=require('acorn-walk');
const src=fs.readFileSync('app.js','utf8');
const ast=acorn.parse(src,{ecmaVersion:2022,sourceType:'script'});
// top-level declarations
const decl=new Map();
for (const n of ast.body) {
  if (n.type==='FunctionDeclaration') decl.set(n.id.name,0);
  if (n.type==='VariableDeclaration') n.declarations.forEach(d=>{ if (d.id.type==='Identifier') decl.set(d.id.name,0); });
  if (n.type==='ClassDeclaration') decl.set(n.id.name,0);
}
// all identifiers referenced
const refs=new Map(); const declaredAnywhere=new Set();
walk.fullAncestor(ast,(node,anc)=>{
  if (node.type==='Identifier') {
    const p=anc[anc.length-2];
    if (p && p.type==='MemberExpression' && p.property===node && !p.computed) return;
    if (p && (p.type==='Property') && p.key===node && !p.computed && !p.shorthand) return;
    if (p && (p.type==='VariableDeclarator') && p.id===node) { declaredAnywhere.add(node.name); return; }
    if (p && (p.type==='FunctionDeclaration'||p.type==='FunctionExpression') && p.id===node) { declaredAnywhere.add(node.name); return; }
    if (p && (p.type==='FunctionDeclaration'||p.type==='FunctionExpression'||p.type==='ArrowFunctionExpression') && p.params.includes(node)) { declaredAnywhere.add(node.name); return; }
    refs.set(node.name,(refs.get(node.name)||0)+1);
  }
});
walk.full(ast,n=>{ if(n.type==='VariableDeclarator'){ const add=x=>{ if(!x) return; if(x.type==='Identifier') declaredAnywhere.add(x.name); else if(x.type==='ObjectPattern') x.properties.forEach(p=>add(p.value||p.argument)); else if(x.type==='ArrayPattern') x.elements.forEach(add); else if (x.type==='AssignmentPattern') add(x.left); else if(x.type==='RestElement') add(x.argument); }; add(n.id);} 
  if(['FunctionDeclaration','FunctionExpression','ArrowFunctionExpression'].includes(n.type)) { const add=x=>{ if(!x) return; if(x.type==='Identifier') declaredAnywhere.add(x.name); else if(x.type==='ObjectPattern') x.properties.forEach(p=>add(p.value||p.argument)); else if(x.type==='ArrayPattern') x.elements.forEach(add); else if (x.type==='AssignmentPattern') add(x.left); else if(x.type==='RestElement') add(x.argument); }; n.params.forEach(add); if (n.id) declaredAnywhere.add(n.id.name); }
  if (n.type==='CatchClause' && n.param) declaredAnywhere.add(n.param.name);
});
const globals=new Set(Object.getOwnPropertyNames(globalThis).concat(['window','document','navigator','localStorage','location','history','matchMedia','requestAnimationFrame','cancelAnimationFrame','getComputedStyle','alert','confirm','crypto','performance','Touch','TouchEvent','File','Blob','FileReader','URL','Image','AudioContext','Notification','screen','innerWidth','innerHeight','scrollY','scrollTo','undefined','arguments','fetch','IntersectionObserver','ResizeObserver','HTMLElement','Event','CustomEvent','self','caches','addEventListener','visualViewport']));
const undef=[...refs.keys()].filter(k=>!declaredAnywhere.has(k)&&!globals.has(k));
console.log('REFERENCED BUT NEVER DECLARED:', undef.join(', ')||'none');
const unused=[...decl.keys()].filter(k=>(refs.get(k)||0)===0);
console.log('TOP-LEVEL DECLARED BUT NEVER USED:', unused.join(', ')||'none');
