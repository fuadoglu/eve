import fs from 'node:fs';
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const api=read('docs/03-engineering/openapi.json');
const db=read('docs/03-engineering/data-dictionary.json');
const work=read('docs/05-delivery/work-packages.json');
const acceptance=read('docs/04-quality/acceptance-scenarios.json');
const operations=Object.values(api.paths).flatMap(p=>Object.entries(p).filter(([m])=>['get','post','patch','put','delete'].includes(m)).map(([,o])=>o));
const ids=ns=>ns.map(n=>'UI'+String(n).padStart(2,'0'));
const task=ns=>ns.map(n=>'EVE-'+String(n).padStart(3,'0'));
const config=[
 ['Şifrəsiz giriş',[1,2,3,18],[3,7]],
 ['Tenant və çox ev',[6,7,16],[6,8]],
 ['Çoxsahibli menecer',[6,7,16],[6,8]],
 ['Rezervasiya və təqvim',[4,5,8],[10,11,12,13]],
 ['Kirayə pul uçotu',[7,8],[11,14,15]],
 ['Xərclər',[7,9],[16]],
 ['Tapşırıq və paylaşım',[9,12],[17,18]],
 ['Hazırlıq və təmizlik',[4,7,9],[12,13,18]],
 ['İnventar və təhvil',[10,11],[19,20,21]],
 ['Çoxdilli QR təlimatı',[13,15],[22,23]],
 ['Public təqdimat',[14],[24,25]],
 ['Ev üzrə SaaS abunə',[6,17],[8,26,27,28]],
 ['Mobil UX və sürət',[1,4,5,6,8,9,11,12,14,15],[2,9,30]],
 ['Audit, export və istismar',[18,19],[29,30]],
 ['İlkin quraşdırma və import',[6,10,18],[19,29]],
 ['Bildirişlər',[4,18],[18]]
];
const rows=config.map(([title,screens,parents],i)=>{
 const id='R'+String(i+1).padStart(2,'0');const parent=task(parents);
 return {id,title,source:'docs/01-product/PRD.md',screens:ids(screens),operations:operations.filter(o=>o['x-requirements'].includes(id)).map(o=>o.operationId).sort(),tables:db.tables.filter(t=>t.requirements.includes(id)).map(t=>t.name).sort(),parent_tasks:parent,packages:work.packages.filter(p=>parent.includes(p.parent)).map(p=>p.id),acceptance:acceptance.scenarios.filter(s=>s.requirements.includes(id)).map(s=>s.id)};
});
fs.writeFileSync('docs/04-quality/traceability.json',JSON.stringify({schema_version:1,generation:'node scripts/generate-traceability.mjs; UI/task mapping reviewed, operations/tables/tests derived from versioned contracts.',requirements:rows},null,2)+'\n');
const md=['# Tələb → ekran → müqavilə → task → test','', 'Maşın mənbəyi: [traceability.json](traceability.json). API/data/test dəyişəndə bu xəritə yenilənir; yoxlayıcı köhnəlmiş əməliyyat və cədvəl əlaqəsini rədd edir. Sadəcə ID-nin mövcudluğunu yoxlamaqla kifayətlənmir.','', '| Tələb | Ekranlar | API / cədvəl sayı | Parent task | Qəbul |','|---|---|---|---|---|'];
for(const r of rows)md.push(`| ${r.id} — ${r.title} | ${r.screens.join(', ')} | ${r.operations.length} / ${r.tables.length} | ${r.parent_tasks.join(', ')} | ${r.acceptance.join(', ')} |`);
md.push('','## Oxuma nümunəsi','','R09 → UI10/UI11 → inventory/inspection API əməliyyatları → data dictionary-də R09 cədvəlləri → EVE-019–021 və onların .1/.2/.3 paketləri → AT17–19. Dəqiq operationId və cədvəl adları JSON xəritəsindədir.','','UI və task əlaqəsi insan tərəfindən review edilir; avtomatik hesablama biznes mənasının doğruluğunu təkbaşına sübut etmir. Acceptance nəticələri ayrıca evidence-dədir.');
fs.writeFileSync('docs/04-quality/TRACEABILITY.md',md.join('\n')+'\n');
console.log(`Generated traceability for ${rows.length} requirements.`);
