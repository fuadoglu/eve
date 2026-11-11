import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const api=read('docs/03-engineering/openapi.json');
const db=read('docs/03-engineering/data-dictionary.json');
const state=read('docs/01-product/state-machines.json');
const config=read('docs/01-product/configuration.json');
const work=read('docs/05-delivery/work-packages.json');
const scenarios=read('docs/04-quality/acceptance-scenarios.json');
const trace=read('docs/04-quality/traceability.json');
const bindings=read('docs/03-engineering/field-bindings.json');
const errors=[];
const assert=(ok,msg)=>{if(!ok)errors.push(msg)};
const same=(a,b)=>JSON.stringify([...a].sort())===JSON.stringify([...b].sort());
const unique=(a,label)=>assert(new Set(a).size===a.length,`${label}: duplicate`);
const reqs=new Set(Array.from({length:16},(_,i)=>'R'+String(i+1).padStart(2,'0')));
const tests=new Set(Array.from({length:36},(_,i)=>'AT'+String(i+1).padStart(2,'0')));
function references(node,doc,where){
  if(!node||typeof node!=='object')return;
  if(typeof node.$ref==='string'){
    assert(node.$ref.startsWith('#/'),`${where}: external ref not pinned`);
    let target=doc;
    for(const s of node.$ref.slice(2).split('/'))target=target?.[s.replace(/~1/g,'/').replace(/~0/g,'~')];
    assert(target!==undefined,`${where}: broken ref ${node.$ref}`);
  }
  for(const [k,v]of Object.entries(node))references(v,doc,where+'/'+k);
}
references(api,api,'OpenAPI');
assert(/^3\.1\./.test(api.openapi),'OpenAPI must be 3.1');
const methods=new Set(['get','post','put','patch','delete','head','options']);
const operations=[];
for(const [url,item]of Object.entries(api.paths))for(const [method,op]of Object.entries(item)){
  if(!methods.has(method))continue;
  operations.push({...op,url,method});
  assert(op.operationId&&op.summary,`${method} ${url}: identity`);
  assert(op['x-capability']&&op['x-entitlement'],`${op.operationId}: auth metadata`);
  assert(op['x-requirements']?.length,`${op.operationId}: requirements`);
  for(const r of op['x-requirements']||[])assert(reqs.has(r),`${op.operationId}: unknown ${r}`);
  assert(Object.keys(op.responses||{}).some(s=>/^2\d\d$/.test(s)),`${op.operationId}: success response`);
  for(const match of url.matchAll(/\{([^}]+)\}/g)){
    const parameters=[...(item.parameters||[]),...(op.parameters||[])].map(p=>p.$ref?api.components.parameters[p.$ref.split('/').at(-1)]:p);
    assert(parameters.some(p=>p?.in==='path'&&p.name===match[1]&&p.required===true),`${op.operationId}: missing path param ${match[1]}`);
  }
  if(method==='get')assert(!op.requestBody,`${op.operationId}: GET body forbidden`);
}
unique(operations.map(o=>o.operationId),'Operation IDs');
const tables=new Map(db.tables.map(t=>[t.name,t]));
unique(db.tables.map(t=>t.name),'Tables');
const external=new Set(Array.isArray(db.external_tables)?db.external_tables.map(t=>typeof t==='string'?t:t.name):Object.keys(db.external_tables||{}));
for(const t of db.tables){
  const cols=new Set(t.columns.map(c=>c.name));
  unique(t.columns.map(c=>c.name),`${t.name} columns`);
  assert(t.rls?.enabled===true,`${t.name}: RLS must be explicit/enabled`);
  assert(t.primary_key?.length,`${t.name}: primary key`);
  for(const c of t.columns){
    assert(c.type&&typeof c.nullable==='boolean'&&Object.hasOwn(c,'default')&&c.description,`${t.name}.${c.name}: incomplete field`);
    if(c.type.startsWith('enum:'))assert(db.enums[c.type.slice(5)],`${t.name}.${c.name}: unknown enum`);
  }
  for(const c of t.primary_key)assert(cols.has(c),`${t.name}: unknown PK ${c}`);
  for(const k of t.unique||[])for(const c of k.columns)assert(cols.has(c),`${t.name}: unknown unique ${c}`);
  for(const fk of t.foreign_keys||[]){
    for(const c of fk.columns)assert(cols.has(c),`${t.name}: unknown local FK ${c}`);
    assert(fk.columns.length===fk.references.columns.length,`${t.name}: FK arity`);
    const target=tables.get(fk.references.table);
    assert(target||external.has(fk.references.table),`${t.name}: unknown FK table ${fk.references.table}`);
    if(target){
      const targetCols=new Set(target.columns.map(c=>c.name));
      for(const c of fk.references.columns)assert(targetCols.has(c),`${t.name}: unknown target FK ${c}`);
      assert(same(target.primary_key,fk.references.columns)||(target.unique||[]).some(u=>!u.predicate&&same(u.columns,fk.references.columns)),`${t.name}: FK target not unconditionally unique`);
    }
    assert(fk.on_delete&&fk.on_update,`${t.name}: FK delete/update semantics`);
  }
  for(const r of t.requirements||[])assert(reqs.has(r),`${t.name}: unknown requirement ${r}`);
}
function scalar(schema){
  if(schema?.$ref)return scalar(api.components.schemas[schema.$ref.split('/').at(-1)]);
  if(schema?.anyOf)return scalar(schema.anyOf.find(x=>x.type!=='null'));
  return schema;
}
unique(bindings.bindings.map(b=>b.schema+'.'+b.api_field),'Field bindings');
for(const b of bindings.bindings){
  const field=scalar(api.components.schemas[b.schema]?.properties?.[b.api_field]);
  const column=tables.get(b.table)?.columns.find(c=>c.name===b.column);
  assert(field&&column,`${b.schema}.${b.api_field}: broken field binding`);
  if(!field||!column)continue;
  const varchar=/^varchar\((\d+)\)$/.exec(column.type);
  if(varchar&&field.type==='string')assert(field.maxLength&&field.maxLength<=Number(varchar[1]),`${b.schema}.${b.api_field}: API length exceeds ${b.table}.${b.column}`);
  if(column.type.startsWith('enum:')){
    const values=db.enums[column.type.slice(5)]?.values||[];
    assert(field.enum&&field.enum.every(x=>values.includes(x)),`${b.schema}.${b.api_field}: enum outside DB`);
  }
}
for(const b of bindings.enum_bindings){
  const field=scalar(api.components.schemas[b.schema]?.properties?.[b.api_field]);
  const values=db.enums[b.db_enum]?.values;
  assert(field?.enum&&values,`${b.schema}.${b.api_field}: missing enum binding`);
  if(field?.enum&&values)assert(b.mode==='subset'?field.enum.every(x=>values.includes(x)):same(field.enum,values),`${b.schema}.${b.api_field}: enum binding mismatch`);
}
for(const b of bindings.computed_fields)assert(api.components.schemas[b.schema]?.properties?.[b.api_field]&&b.rule,`${b.schema}.${b.api_field}: computed contract missing`);
for(const m of state.machines){
  unique(m.states,`${m.name} states`);
  unique(m.transitions.map(t=>t.id),`${m.name} transitions`);
  for(const t of m.transitions){
    assert(t.from_states.every(s=>m.states.includes(s)),`${t.id}: invalid source`);
    assert(t.to_state==='same'||m.states.includes(t.to_state),`${t.id}: invalid destination`);
    assert(t.preconditions.length&&t.transaction_effects.length&&t.capability,`${t.id}: incomplete behavior`);
    for(const r of t.requirements)assert(reqs.has(r),`${t.id}: requirement ${r}`);
    for(const a of t.acceptance)assert(tests.has(a),`${t.id}: acceptance ${a}`);
  }
}
unique(config.policies.map(p=>p.key),'Configuration keys');
for(const p of config.policies)assert(reqs.has(p.requirement)&&tests.has(p.acceptance)&&p.rationale&&p.unit&&typeof p.mutable==='boolean',`${p.key}: config metadata`);
const packages=new Map(work.packages.map(p=>[p.id,p]));
unique(work.packages.map(p=>p.id),'Work packages');
assert(packages.size===90,'Exactly 90 packages expected');
const visiting=new Set(),visited=new Set();
function visit(id){
  assert(packages.has(id),`Unknown package dependency ${id}`);
  if(!packages.has(id)||visited.has(id))return;
  if(visiting.has(id)){errors.push(`Dependency cycle at ${id}`);return;}
  visiting.add(id);
  for(const d of packages.get(id).depends_on)visit(d);
  visiting.delete(id);visited.add(id);
}
for(const p of work.packages){
  assert(p.parent_issue&&p.deliverable&&p.acceptance.length&&p.owned_path_candidates.length,`${p.id}: incomplete task`);
  visit(p.id);
}
assert(scenarios.scenarios.length===36,'Exactly 36 acceptance scenarios expected');
for(const s of scenarios.scenarios)assert(tests.has(s.id)&&s.given&&s.when&&s.then&&s.requirements.every(r=>reqs.has(r)),`${s.id}: scenario incomplete`);
unique(scenarios.scenarios.map(s=>s.id),'Acceptance IDs');
assert(trace.requirements.length===16,'Exactly 16 trace rows expected');
unique(trace.requirements.map(r=>r.id),'Trace requirements');
for(const r of trace.requirements){
  assert(reqs.has(r.id)&&r.screens.length&&r.parent_tasks.length&&r.acceptance.length,`${r.id}: trace incomplete`);
  assert(same(r.operations,operations.filter(o=>o['x-requirements'].includes(r.id)).map(o=>o.operationId)),`${r.id}: operation trace stale`);
  assert(same(r.tables,db.tables.filter(t=>t.requirements.includes(r.id)).map(t=>t.name)),`${r.id}: table trace stale`);
  assert(same(r.acceptance,scenarios.scenarios.filter(s=>s.requirements.includes(r.id)).map(s=>s.id)),`${r.id}: acceptance trace stale`);
  for(const p of r.packages)assert(packages.has(p),`${r.id}: missing package ${p}`);
  for(const a of r.acceptance)assert(tests.has(a),`${r.id}: missing acceptance ${a}`);
  for(const s of r.screens)assert(/^UI\d{2}$/.test(s)&&Number(s.slice(2))<=19,`${r.id}: invalid screen ${s}`);
}
const prd=fs.readFileSync(path.join(root,'docs/01-product/PRD.md'),'utf8');
const prdRows=new Map();
for(const line of prd.split('\n')){
  const row=line.match(/^\|\s*(R\d{2})\s*\|[^|]*\|\s*([^|]+)\|/);
  if(!row)continue;
  assert(!prdRows.has(row[1]),`${row[1]}: duplicate PRD requirement`);
  const ids=[];
  for(const m of row[2].matchAll(/AT(\d{2})(?:[–-](\d{2}))?/g)){
    const start=Number(m[1]),end=m[2]?Number(m[2]):start;
    assert(end>=start&&end<=36,`${row[1]}: invalid PRD acceptance range`);
    for(let i=start;i<=end;i++)ids.push('AT'+String(i).padStart(2,'0'));
  }
  assert(ids.length>0,`${row[1]}: PRD acceptance missing`);
  prdRows.set(row[1],ids);
}
assert(prdRows.size===16,'PRD must contain exactly 16 requirements');
const traceMd=fs.readFileSync(path.join(root,'docs/04-quality/TRACEABILITY.md'),'utf8');
for(const r of trace.requirements){
  assert(prdRows.has(r.id)&&prdRows.get(r.id).every(a=>r.acceptance.includes(a)),`${r.id}: PRD acceptance trace stale`);
  const expected=`| ${r.id} — ${r.title} | ${r.screens.join(', ')} | ${r.operations.length} / ${r.tables.length} | ${r.parent_tasks.join(', ')} | ${r.acceptance.join(', ')} |`;
  assert(traceMd.split('\n').includes(expected),`${r.id}: Markdown trace stale`);
}
const prototype=fs.readFileSync(path.join(root,'docs/02-design/prototype.html'),'utf8');
let scripts=0;
for(const m of prototype.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)){
  if(m[1].trim()){new Function(m[1]);scripts++;}
}
assert(scripts>0,'Prototype JavaScript missing');
if(errors.length){console.error(errors.join('\n'));process.exitCode=1;}
else console.log(`Contracts OK: ${operations.length} operations; ${db.tables.length} tables; ${bindings.bindings.length} field bindings; ${work.packages.length} acyclic packages; 16 trace rows; 36 scenarios; prototype syntax.`);
