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
function resolveLocal(node){
  const seen=new Set();
  while(node?.$ref){
    if(seen.has(node.$ref)){errors.push(`Cyclic OpenAPI ref ${node.$ref}`);return undefined;}
    seen.add(node.$ref);
    let target=api;
    for(const part of node.$ref.slice(2).split('/'))target=target?.[part.replace(/~1/g,'/').replace(/~0/g,'~')];
    node=target;
  }
  return node;
}
const hasPayloadSchema=media=>typeof resolveLocal(media?.schema)?.type==='string';
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
const publicOperations=new Map([
  ['requestEmailLink','anonymous.email_link'],['confirmEmailLink','anonymous.email_confirm'],
  ['readPublicProperty','public.published.read'],['readPublicAvailability','public.availability.read'],
  ['quotePublicStay','public.quote'],['readPublicGuide','public.guide.read'],
  ['receivePayriffEvent','provider.verify'],['readPublicGuideIndex','public.guide.read'],
  ['exchangeScopedLink','anonymous.link_exchange']
]);
const scopedOperations=new Map([
  ['readScopedTask','link.task.read'],['acceptScopedTask','link.task.accept'],
  ['reportScopedTaskDone','link.task.report_done'],['readScopedInspection','link.inspection.read'],
  ['saveScopedInspection','link.inspection.write'],['completeScopedInspection','link.inspection.complete'],
  ['createScopedUpload','link.media.write'],['finalizeScopedUpload','link.media.write'],
  ['readGuestGuide','link.guest_guide.read'],['getScopedMediaAccess','link.media.read'],
  ['readScopedMediaContent','link.media.read']
]);
const expectedSecurity={session:[{SessionCookie:[]}],scoped:[{ScopedLink:[]}],public:[]};
assert(JSON.stringify(api.security)===JSON.stringify(expectedSecurity.session),'OpenAPI: global SessionCookie security required');
const operations=[];
for(const [url,item]of Object.entries(api.paths))for(const [method,op]of Object.entries(item)){
  if(!methods.has(method))continue;
  operations.push({...op,url,method});
  assert(op.operationId&&op.summary,`${method} ${url}: identity`);
  assert(op['x-capability']&&op['x-entitlement'],`${op.operationId}: auth metadata`);
  assert(op.security!==undefined||api.security!==undefined,`${op.operationId}: security missing`);
  const securityClass=publicOperations.has(op.operationId)?'public':scopedOperations.has(op.operationId)?'scoped':'session';
  assert(JSON.stringify(op.security??api.security)===JSON.stringify(expectedSecurity[securityClass]),`${op.operationId}: security boundary mismatch`);
  if(securityClass!=='session')assert(op['x-capability']===(securityClass==='public'?publicOperations:scopedOperations).get(op.operationId),`${op.operationId}: security capability mismatch`);
  assert(op['x-requirements']?.length,`${op.operationId}: requirements`);
  for(const r of op['x-requirements']||[])assert(reqs.has(r),`${op.operationId}: unknown ${r}`);
  assert(Object.keys(op.responses||{}).some(s=>/^2\d\d$/.test(s)),`${op.operationId}: success response`);
  for(const [status,response] of Object.entries(op.responses||{})){
    const payload=resolveLocal(response);
    if(status==='204')continue;
    assert(Object.values(payload?.content||{}).some(hasPayloadSchema),`${op.operationId}: ${status} response schema missing`);
  }
  if(op.requestBody)assert(Object.values(resolveLocal(op.requestBody)?.content||{}).some(hasPayloadSchema),`${op.operationId}: request schema missing`);
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
  if(varchar&&field.type==='string')assert(field.maxLength===Number(varchar[1]),`${b.schema}.${b.api_field}: API/DB length mismatch at ${b.table}.${b.column}`);
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
const machineEnums={reservation:'reservation_state',task:'task_state',inspection:'submission_state',expense:'expense_approval',billing_order:'order_state'};
const stateCapabilityApis={
  'reservation.write':['reservation.write','reservation.write_both_properties'],
  'system.hold_expiry':[],
  'task.manage':['task.manage'],
  'task.accept':['task.manage','link.task.accept'],
  'task.complete':['task.manage','link.task.report_done'],
  'inspection.submit':['inventory.manage','link.inspection.write','link.inspection.complete'],
  'inventory.manage':['inventory.manage'],
  'expense.propose':['expense.propose'],
  'finance.manage':['finance.manage'],
  'billing.owner':['owner'],
  'system.billing':[],
  'operator.allowlisted':['operator.allowlisted']
};
const apiCapabilities=new Set(operations.map(op=>op['x-capability']));
for(const [capability,aliases] of Object.entries(stateCapabilityApis))for(const alias of aliases)assert(apiCapabilities.has(alias),`${capability}: API capability ${alias} missing`);
const operatorReview=operations.find(op=>op.operationId==='reviewOperatorOrder');
assert(operatorReview?.['x-capability']==='operator.allowlisted','reviewOperatorOrder: operator capability required');
for(const m of state.machines){
  unique(m.states,`${m.name} states`);
  unique(m.transitions.map(t=>t.id),`${m.name} transitions`);
  const values=db.enums[machineEnums[m.name]]?.values;
  assert(values&&same(m.states.filter(s=>s!=='absent'),values),`${m.name}: DB state enum mismatch`);
  assert(m.terminal_states.every(s=>m.states.includes(s)),`${m.name}: unknown terminal state`);
  for(const t of m.transitions){
    assert(t.from_states.every(s=>m.states.includes(s)),`${t.id}: invalid source`);
    assert(t.to_state==='same'||m.states.includes(t.to_state),`${t.id}: invalid destination`);
    assert(t.preconditions.length&&t.transaction_effects.length&&t.capability,`${t.id}: incomplete behavior`);
    assert(Object.hasOwn(stateCapabilityApis,t.capability),`${t.id}: unmapped capability ${t.capability}`);
    if(t.id==='billing_order.review_refund'||t.id==='billing_order.review_chargeback'){
      const expectedState=t.id==='billing_order.review_refund'?'refund_review':'chargeback_review';
      assert(t.capability===operatorReview?.['x-capability'],`${t.id}: operator capability mismatch`);
      assert(t.from_states.length===1&&t.from_states[0]==='entitlement_applied',`${t.id}: invalid review source`);
      assert(t.to_state===expectedState,`${t.id}: invalid review destination`);
      assert(t.preconditions.includes('operator_allowlisted')&&t.preconditions.includes('reason_and_expected_version_required'),`${t.id}: review authorization preconditions missing`);
      assert(same(t.transaction_effects,['record_review_marker_and_reason_audit','preserve_payment_and_entitlement']),`${t.id}: review effects must preserve payment and entitlement`);
    }
    assert(!t.from_states.some(s=>m.terminal_states.includes(s)&&t.to_state!=='same'),`${t.id}: terminal state transition`);
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
  const candidate=line.match(/^ {0,3}\|\s*(R\d+)/);
  if(!candidate)continue;
  assert(reqs.has(candidate[1]),`${candidate[1]}: unknown PRD requirement`);
  const row=line.match(/^ {0,3}\|\s*(R\d+)\s*\|[^|]*\|\s*([^|]+)\|/);
  if(!row){errors.push(`${candidate[1]}: invalid PRD requirement row`);continue;}
  assert(!prdRows.has(row[1]),`${row[1]}: duplicate PRD requirement`);
  assert(/^AT\d{2}(?:[–-]\d{2})?(?:\s*,\s*AT\d{2}(?:[–-]\d{2})?)*$/.test(row[2].trim()),`${row[1]}: invalid PRD acceptance syntax`);
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
const markdownRows=traceMd.split('\n').map(line=>({line,match:line.match(/^ {0,3}\|\s*(R\d+)/)})).filter(x=>x.match);
assert(markdownRows.length===16,'Markdown trace must contain exactly 16 requirement rows');
for(const row of markdownRows)assert(reqs.has(row.match[1]),`${row.match[1]}: unknown Markdown requirement`);
for(const r of trace.requirements){
  assert(prdRows.has(r.id)&&prdRows.get(r.id).every(a=>r.acceptance.includes(a)),`${r.id}: PRD acceptance trace stale`);
  const expected=`| ${r.id} — ${r.title} | ${r.screens.join(', ')} | ${r.operations.length} / ${r.tables.length} | ${r.parent_tasks.join(', ')} | ${r.acceptance.join(', ')} |`;
  const matching=markdownRows.filter(row=>row.match[1]===r.id);
  assert(matching.length===1&&matching[0].line===expected,`${r.id}: Markdown trace stale`);
}
const prototype=fs.readFileSync(path.join(root,'docs/02-design/prototype.html'),'utf8');
let scripts=0;
for(const m of prototype.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)){
  if(m[1].trim()){new Function(m[1]);scripts++;}
}
assert(scripts>0,'Prototype JavaScript missing');
if(errors.length){console.error(errors.join('\n'));process.exitCode=1;}
else console.log(`Contracts OK: ${operations.length} operations; ${db.tables.length} tables; ${bindings.bindings.length} field bindings; ${work.packages.length} acyclic packages; 16 trace rows; 36 scenarios; prototype syntax.`);
