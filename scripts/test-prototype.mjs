import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

// Sənəd prototipi üçün yaddaşdaxili DOM smoke testidir.
// Layout, CSS, browser accessibility, real cihaz və backend testi DEYİL.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(path.join(root, 'docs/02-design/prototype.html'), 'utf8');
const script = source.match(/<script>([\s\S]*)<\/script>/)?.[1];
assert.ok(script, 'Prototipin inline script-i tapılmalıdır');
new Function(script); // Sintaksis yoxlaması; faktiki DOM aşağıdakı stub-dur.

const elements = new Map();
const events = new Map();
let assertions = 0;
const check = (condition, message) => {
  assertions += 1;
  assert.ok(condition, message);
};
function element(selector) {
  if (!elements.has(selector)) {
    const classes = new Set();
    elements.set(selector, {
      innerHTML: '', textContent: '', value: 'normal', open: false,
      classList: {
        add: name => classes.add(name),
        remove: name => classes.delete(name),
        toggle(name, force) {
          const enabled = force ?? !classes.has(name);
          if (enabled) classes.add(name); else classes.delete(name);
          return enabled;
        },
        contains: name => classes.has(name),
      },
      addEventListener(type, callback) {
        events.set(`${selector}:${type}`, callback);
      },
      focus() {}, scrollIntoView() {},
      showModal() { this.open = true; },
      close() { this.open = false; },
    });
  }
  return elements.get(selector);
}
class FakeFormData {
  constructor(form) { this.values = form.values ?? {}; }
  get(key) { return this.values[key] ?? null; }
}
const context = {
  document: {
    querySelector: element,
    addEventListener: (type, callback) => events.set(`document:${type}`, callback),
  },
  window: { scrollTo() {}, isSecureContext: false },
  navigator: {},
  setTimeout: () => 0,
  clearTimeout() {},
  FormData: FakeFormData,
  console,
};
vm.createContext(context);
vm.runInContext(script, context, { filename: 'prototype-inline.js', timeout: 1000 });
const run = code => vm.runInContext(code, context, { timeout: 1000 });
const main = () => element('#main').innerHTML;
function click(dataset) {
  const button = { dataset };
  events.get('document:click')({ target: { closest: () => button } });
}
function submit(kind, values = {}, id = 'demo-form') {
  let prevented = false;
  events.get('document:submit')({
    target: { id, dataset: { kind }, values },
    preventDefault() { prevented = true; },
  });
  check(prevented, `${id}/${kind}: default reload-un qarşısı alınmalıdır`);
}

const screens = run('screens.map(item => item[0])');
check(screens.length === 19, 'UI01–19: 19 ekran olmalıdır');
for (const screen of screens) {
  run(`go(${JSON.stringify(screen)})`);
  check(main().length > 80, `${screen}: boş render olmamalıdır`);
}
for (const state of ['normal', 'empty', 'loading', 'error', 'noaccess', 'offline']) {
  run(`page='today'; viewState=${JSON.stringify(state)}; render()`);
  check(main().length > 50, `${state}: render məzmunu olmalıdır`);
}
for (const kind of ['reservation', 'money', 'refund', 'expense', 'task', 'cancel']) {
  run(`form(${JSON.stringify(kind)})`);
  check(element('#sheet-body').innerHTML.includes('demo-form'), `${kind}: forma açılmalıdır`);
}

// Email axını yalnız ekran keçididir, real email/sessiya yoxdur.
run("go('login')");
element('#email').value = 'demo@example.com';
submit(undefined, {}, 'login-form');
check(run('page') === 'checkemail', 'Email formu checkemail ekranına keçməlidir');
check(main().includes('demo@example.com'), 'Email düzəliş üçün görünməlidir');

// Tarix xəta verəndə modal bağlanmır, nümunə məlumat itmir.
run("go('today'); form('reservation')");
submit('reservation', { checkin: '2026-11-14', checkout: '2026-11-11', guest: 'Demo', total: '300' });
check(element('#form-error').textContent.includes('Çıxış'), 'Əks tarix aralığı rədd edilməlidir');
check(element('#sheet').open, 'Xətalı forma açıq qalmalıdır');
submit('reservation', { checkin: '2026-11-11', checkout: '2026-11-14', guest: 'Demo', total: '300' });
check(!element('#sheet').open, 'Düzgün nümunə submit modalı bağlamalıdır');

// Offline heç bir nümunə maliyyə dəyişikliyini uğur saymır.
run("page='reservation';viewState='offline';received=100;form('money')");
submit('money', { amount: '50', 'money-kind': 'rent' });
check(run('received') === 100, 'Offline rent balansı dəyişməməlidir');
check(element('#form-error').textContent.includes('Bağlantı yoxdur'), 'Offline xəta görünməlidir');
run("viewState='normal';form('money')");
submit('money', { amount: '50', 'money-kind': 'rent' });
check(run('received') === 150, 'Rent nümunə balansı 150 olmalıdır');
run("form('money')");
submit('money', { amount: '100', 'money-kind': 'deposit' });
check(run('received') === 150, 'Depozit rent balansına əlavə edilməməlidir');
run("form('refund')");
submit('refund', { amount: '25', 'money-kind': 'rent' });
check(run('received') === 125, 'Refund nümunə rent balansını azaltmalıdır');

// Public yalnız uyğun gecə və onlardan sonra qanuni çıxış sərhədi verir.
run("page='public';viewState='normal';publicDates=[];render()");
let day14 = main().match(/<button[^>]*data-day="14"[^>]*>/)?.[0];
check(day14?.includes('disabled'), '14 noyabr ilkin giriş/gecə kimi seçilməməlidir');
click({ day: '11', public: 'true' });
day14 = main().match(/<button[^>]*data-day="14"[^>]*>/)?.[0];
check(day14 && !day14.includes('disabled'), '11-dən sonra 14 etibarlı çıxış ola bilər');
click({ day: '14', public: 'true' });
check(run('publicDates.join(",")') === '11,14', 'Public aralıq 11–14 olmalıdır');
check(!main().includes('Dolu') && !main().includes('bloklanıb'), 'Public dolu/blok səbəbi göstərməməlidir');
check(element('.shell').classList.contains('guest'), 'Public owner panel naviqasiyasını gizlətməlidir');

for (const locale of ['az', 'ru', 'en']) {
  run(`page='guide';lang=${JSON.stringify(locale)};render()`);
  check(main().includes(`data-lang="${locale}" aria-pressed="true"`), `${locale}: aktiv dil görünməlidir`);
}

// GET/render inventarı əvvəlcədən tamamlanmış göstərməməlidir.
run("page='inspection';viewState='normal';answers={};inspectionDone=false;render()");
check(!main().includes('selected-ok'), 'İnventar əvvəlcədən təsdiqlənməməlidir');
check(main().includes('0/4 cavab'), 'İlkin inventar cavab sayı sıfırdır');
element('#inspector-name').value = 'Nümunə yoxlayan';
click({ action: 'complete-inspection' });
check(!run('inspectionDone'), 'Cavabsız yoxlama tamamlanmamalıdır');
check(element('#inspection-error').textContent.includes('Hər otağa'), 'Tamamlanmayan otaq xətası olmalıdır');
run("answers={living:{type:'ok'},kitchen:{type:'ok'},bed:{type:'ok'},bath:{type:'unable',reason:''}}");
click({ action: 'complete-inspection' });
check(!run('inspectionDone'), 'Yoxlanmama səbəbi olmadan bitməməlidir');
run("answers.bath.reason='Otaq bağlı idi'");
click({ action: 'complete-inspection' });
check(run('inspectionDone'), 'Bütün otaqlar cavablandırıldıqda nümunə kilidlənməlidir');
check(main().includes('Serverə və heç bir şəxsə göndərilməyib'), 'Completion real göndəriş iddia etməməlidir');

// İşçi report və sahib confirm ayrı hadisələrdir; GET/render dəyişmir.
run("page='worker';taskState='open';render()");
check(run('taskState') === 'open', 'Task render avtomatik qəbul etməməlidir');
click({ action: 'report-task' });
check(run('taskState') === 'open', 'Qəbuldan əvvəl report rədd edilməlidir');
click({ action: 'accept-task' });
check(run('taskState') === 'accepted', 'Explicit qəbul statusu olmalıdır');
click({ action: 'report-task' });
check(run('taskState') === 'reported_done', 'İşçi yalnız report edir');
run("page='task';render()");
click({ action: 'report-task' });
check(run('taskState') === 'completed', 'Sahib təsdiqi completion edir');
click({ action: 'accept-task' });
check(run('taskState') === 'completed', 'Completed iş yenidən qəbul olunmamalıdır');

check(!/localStorage|sessionStorage|fetch\(/.test(script), 'Prototip şəbəkə/persistent storage işlətməməlidir');
console.log(`PASS prototype smoke: ${assertions} assertions; 19 screens; 6 states; 6 forms; public departures; locales; inspection; submit flows.`);
console.log('LIMIT: VM/fake-DOM smoke only. Browser layout, real device, usability and backend tests remain separate.');
