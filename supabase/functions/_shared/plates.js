// Общие правила игры: страны, редкости, генерация номеров.
// Этот же файл импортирует и страница (index.html), и серверные функции — правила в одном месте.

export const AZ = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
export const KANA = 'さすせそたちつてとなにぬねのはひふほまみむめもやゆよらりるろれわ';
export const DIGITS = '0123456789';

export const START_BALANCE = 5000;
export const RTP = 0.95;          // в среднем прокрутка возвращает 95% своей цены (без учёта гаранта)
export const PITY = 10;           // 9 прокруток подряд без редкого — десятая минимум редкая
export const RENT_RATE = 0.005;   // аренда: 0.5% стоимости гаража в час
export const RENT_CAP_H = 24;     // копится максимум за 24 часа
export const MARKET_FEE = 0.05;   // комиссия рынка, сгорает
// Те же числа для аренды, бонуса и коллекций зашиты в supabase/migrations — сервер главный.

// tpl: R — код региона, D — «главные» цифры (по ним считается редкость), L — буквы серии,
// d — случайная цифра, K — хирагана, | — перенос строки, • — наклейки (Германия), остальное как есть.
export const COUNTRIES = [
  {
    id: 'ua', name: 'Украина', mult: 1, tpl: 'R DDDD LL', letters: 'ABCEHIKMOPTX', matchRegion: true,
    regions: {
      AA: 'Киев', KA: 'Киев', AI: 'Киевская обл.', AB: 'Винницкая обл.', AC: 'Волынская обл.',
      AE: 'Днепропетровская обл.', AH: 'Донецкая обл.', AM: 'Житомирская обл.', AO: 'Закарпатская обл.',
      AP: 'Запорожская обл.', AT: 'Ивано-Франковская обл.', AX: 'Харьковская обл.', BA: 'Кировоградская обл.',
      BB: 'Луганская обл.', BC: 'Львовская обл.', BE: 'Николаевская обл.', BH: 'Одесская обл.',
      BI: 'Полтавская обл.', BK: 'Ровенская обл.', BM: 'Сумская обл.', BO: 'Тернопольская обл.',
      BT: 'Херсонская обл.', BX: 'Хмельницкая обл.', CA: 'Черкасская обл.', CB: 'Черниговская обл.',
      CE: 'Черновицкая обл.', AK: 'Крым',
    },
    mythic: ['KOZAK', 'MRIYA', 'PATRON', 'SLAVA', 'BORSCH', 'HETMAN', 'ZSU', 'XAPKIB'],
  },
  {
    id: 'pl', name: 'Польша', mult: 1.1, tpl: 'R DDDLL',
    regions: { WA: 'Варшава', WE: 'Варшава', KR: 'Краков', GD: 'Гданьск', GA: 'Гдыня', PO: 'Познань', DW: 'Вроцлав', LU: 'Люблин', EL: 'Лодзь', ZS: 'Щецин', SK: 'Катовице' },
    mythic: ['W0 SZEF', 'K0 SMOK', 'G1 MORZE', 'W1 BOSS', 'P0 PIWO'],
  },
  { id: 'pt', name: 'Португалия', mult: 1.2, tpl: 'LL-DD-LL', mythic: ['AA-00-AA', 'PT-00-01', 'ZZ-99-ZZ'] },
  { id: 'nl', name: 'Нидерланды', mult: 1.2, tpl: 'LL-DDD-L', mythic: ['AA-1', 'AA-7', 'AA-12'] }, // AA — номера королевской семьи
  { id: 'it', name: 'Италия', mult: 1.3, tpl: 'LL DDDLL', mythic: ['AA 000 AA', 'RM 001 MA', 'ZZ 999 ZZ'] },
  { id: 'fr', name: 'Франция', mult: 1.3, tpl: 'LL-DDD-LL', mythic: ['AA-001-AA', 'PA-075-RS', 'ZZ-999-ZZ'] },
  {
    id: 'de', name: 'Германия', mult: 1.5, tpl: 'R•LL DDDD',
    regions: { B: 'Берлин', M: 'Мюнхен', HH: 'Гамбург', K: 'Кёльн', F: 'Франкфурт', S: 'Штутгарт', D: 'Дюссельдорф', HB: 'Бремен', L: 'Лейпциг', DO: 'Дортмунд' },
    mythic: ['S•PO 911', 'M•BW 1', 'B•ER 1', 'IN•AU 1', 'HH•SV 1'],
  },
  { id: 'uk', name: 'Британия', mult: 1.7, tpl: 'LLDD LLL', mythic: ['F 1', '25 O', 'S 1', 'M 1', '1 D'] },
  { id: 'us', name: 'США · Калифорния', mult: 2, tpl: 'DLLLDDD', mythic: ['BOSS', 'LA LAND', '2FAST4U', 'SURFER', 'HOLYWD'] },
  {
    id: 'jp', name: 'Япония', mult: 2.2, tpl: 'R 3dd|K DD-DD',
    regions: { 品川: 'Синагава', 練馬: 'Нэрима', 横浜: 'Иокогама', 大阪: 'Осака', 京都: 'Киото', 札幌: 'Саппоро', 名古屋: 'Нагоя', 神戸: 'Кобе', 福岡: 'Фукуока', 沖縄: 'Окинава' },
    mythic: ['品川 300|さ ・・・1', '横浜 300|す ・・・7', '京都 300|な ・・88', '大阪 330|わ ・・・8'],
  },
  { id: 'ae', name: 'ОАЭ · Дубай', mult: 3, tpl: 'L DDDDD', mythic: ['P 7', 'A 1', 'B 1', 'AA 9', 'D 5'] },
];
for (const c of COUNTRIES) {
  c.letters ||= AZ;
  c.regionCodes = c.regions ? Object.keys(c.regions) : null;
}
export const countryOf = id => COUNTRIES.find(c => c.id === id);

export const TIERS = [
  { id: 'common',    name: 'Обычный',     color: '#9aa4b1', min: 8,    max: 22,    weight: 55,  rule: 'Случайные символы' },
  { id: 'uncommon',  name: 'Необычный',   color: '#4b8bff', min: 30,   max: 70,    weight: 27,  rule: 'Зеркало 1221, пары 1122, круглые 4500' },
  { id: 'rare',      name: 'Редкий',      color: '#9b5cff', min: 90,   max: 210,   weight: 12,  rule: 'Три одинаковые 7771, тысячи 3000 или одинаковые буквы' },
  { id: 'epic',      name: 'Эпический',   color: '#ec4ccf', min: 300,  max: 600,   weight: 4.3, rule: 'Все цифры одинаковые, лесенка 1234, 0007' },
  { id: 'legendary', name: 'Легендарный', color: '#ffb020', min: 1200, max: 2400,  weight: 1.3, rule: 'Одинаковые цифры + одинаковые буквы' },
  { id: 'mythic',    name: 'Мифический',  color: '#ff3d3d', min: 6000, max: 12000, weight: 0.4, rule: 'Именной или исторический номер — каждый существует в одном экземпляре' },
];
export const tierOf = id => TIERS.find(t => t.id === id);
export const tierIdx = id => TIERS.findIndex(t => t.id === id);
export const RARE_IDX = tierIdx('rare');
const TOTAL_W = TIERS.reduce((s, t) => s + t.weight, 0);
export const tierChance = t => t.weight / TOTAL_W;

export const COLLECTIONS = [
  { id: 'kyiv',     name: 'Киевлянин',      desc: 'Украинские номера AA и KA одновременно',        reward: 500 },
  { id: 'ua10',     name: 'Вся Украина',    desc: 'Номера 10 разных регионов Украины',             reward: 1500 },
  { id: 'euro',     name: 'Евротур',        desc: 'Польша, Португалия, Нидерланды, Италия, Франция и Германия', reward: 2000 },
  { id: 'world',    name: 'Кругосветка',    desc: 'По номеру из каждой из 11 стран',               reward: 6000 },
  { id: 'garage30', name: 'Большой гараж',  desc: '30 номеров в гараже одновременно',              reward: 1000 },
  { id: 'rich',     name: 'Дорогая коллекция', desc: 'Гараж стоимостью от 20 000 ₴',               reward: 2000 },
  { id: 'legend',   name: 'Легенда',        desc: 'Хотя бы один легендарный номер',               reward: 2500 },
  { id: 'myth',     name: 'Миф',            desc: 'Мифический номер — их всего несколько на весь мир', reward: 8000 },
];
const EURO = ['pl', 'pt', 'nl', 'it', 'fr', 'de'];
const uaRegion = p => p.c === 'ua' && p.tier !== 'mythic' ? p.text.split(' ')[0] : null;
// Прогресс коллекции по номерам игрока: { have, need }
export function collectionProgress(id, plates) {
  const countries = new Set(plates.map(p => p.c));
  const regions = new Set(plates.map(uaRegion).filter(Boolean));
  switch (id) {
    case 'kyiv': return { have: ['AA', 'KA'].filter(r => regions.has(r)).length, need: 2 };
    case 'ua10': return { have: Math.min(regions.size, 10), need: 10 };
    case 'euro': return { have: EURO.filter(c => countries.has(c)).length, need: 6 };
    case 'world': return { have: countries.size, need: COUNTRIES.length };
    case 'garage30': return { have: Math.min(plates.length, 30), need: 30 };
    case 'rich': { const v = plates.reduce((s, p) => s + p.value, 0); return { have: Math.min(v, 20000), need: 20000 }; }
    case 'legend': return { have: plates.some(p => p.tier === 'legendary') ? 1 : 0, need: 1 };
    case 'myth': return { have: plates.some(p => p.tier === 'mythic') ? 1 : 0, need: 1 };
  }
}

// ---------- утилиты ----------
export const ri = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
export const pick = a => a[Math.floor(Math.random() * a.length)];
const twoSig = n => { const p = 10 ** Math.max(0, Math.floor(Math.log10(n)) - 1); return Math.round(n / p) * p; };
export const spinPrice = c => twoSig(TIERS.reduce((s, t) => s + tierChance(t) * (t.min + t.max) / 2, 0) * c.mult / RTP);
export const valueFor = (c, tier) => Math.round(ri(tier.min, tier.max) * c.mult);

// ---------- генерация ----------
const SEQ_UP = DIGITS, SEQ_DOWN = '9876543210';
function twoDistinct() { const a = ri(0, 9); let b; do b = ri(0, 9); while (b === a); return [a, b]; }
function isPatterned(d) {
  const n = d.length;
  if (n < 2) return false;
  if (new Set(d).size === 1) return true;
  if (d.startsWith('00')) return true;
  if (n === 2) return d[1] === '0';
  return /(\d)\1\1/.test(d)
    || d === [...d].reverse().join('')
    || d.endsWith('00')
    || SEQ_UP.includes(d) || SEQ_DOWN.includes(d)
    || (n === 4 && ((d[0] === d[1] && d[2] === d[3]) || (d[0] === d[2] && d[1] === d[3])));
}
function plainDigits(n) {
  let d;
  do d = Array.from({ length: n }, () => ri(0, 9)).join(''); while (isPatterned(d));
  return d;
}
function mirror(n) {
  let d;
  do {
    const half = Array.from({ length: Math.ceil(n / 2) }, () => ri(0, 9));
    d = [...half, ...half.slice(0, Math.floor(n / 2)).reverse()].join('');
  } while (new Set(d).size === 1);
  return d;
}
const same = n => String(ri(0, 9)).repeat(n);
const zerosThen = n => '0'.repeat(n - 1) + ri(1, 9);
function seq(n) {
  const src = pick([SEQ_UP, SEQ_DOWN]);
  const s = ri(0, 10 - n);
  return src.slice(s, s + n);
}
function digitsFor(tier, n) {
  if (n === 0) return '';
  if (n === 1) return String(ri(0, 9));
  const [a, b] = twoDistinct();
  switch (tier) {
    case 'common': return plainDigits(n);
    case 'uncommon':
      if (n === 2) return `${ri(1, 9)}0`;
      return pick([
        () => mirror(n),
        () => `${ri(1, 9)}${n > 3 ? ri(1, 9) : ''}`.padEnd(n, '0'),
        ...(n === 4 ? [() => `${a}${a}${b}${b}`, () => `${a}${b}${a}${b}`] : []),
      ])();
    case 'rare':
      if (n === 2) return String(ri(1, 9)).repeat(2);
      return pick([() => String(a).repeat(n - 1) + b, () => b + String(a).repeat(n - 1), () => String(ri(1, 9)).padEnd(n, '0')])();
    case 'epic':
      if (n === 2) return zerosThen(2);
      return pick([() => same(n), () => seq(n), () => zerosThen(n)])();
    case 'legendary':
      return pick([() => same(n), () => zerosThen(n)])();
  }
}
function lettersFor(c, m, region, sameLetters) {
  if (m === 0) return '';
  if (sameLetters) return c.matchRegion && region?.length === m ? region : pick(c.letters).repeat(m);
  let s;
  do s = Array.from({ length: m }, () => pick(c.letters)).join('');
  while (m > 1 && (new Set(s).size === 1 || (c.matchRegion && s === region)));
  return s;
}

// Номер заданной редкости. Для мифических можно передать список ещё свободных.
export function makePlate(c, tier, freeMythic = c.mythic) {
  if (tier === 'mythic') return pick(freeMythic);
  const n = [...c.tpl].filter(x => x === 'D').length;
  const m = [...c.tpl].filter(x => x === 'L').length;
  const region = c.regionCodes ? pick(c.regionCodes) : null;
  let digits, letters;
  if (tier === 'rare' && Math.random() < 0.3) {
    digits = plainDigits(n); letters = lettersFor(c, m, region, true);
  } else {
    digits = digitsFor(tier, n); letters = lettersFor(c, m, region, tier === 'legendary');
  }
  let di = 0, li = 0;
  return [...c.tpl].map(x =>
    x === 'R' ? region : x === 'D' ? digits[di++] : x === 'L' ? letters[li++] :
    x === 'd' ? ri(0, 9) : x === 'K' ? pick(KANA) : x).join('');
}

export function rollTier(minIdx = 0) {
  const pool = TIERS.slice(minIdx);
  let r = Math.random() * pool.reduce((s, t) => s + t.weight, 0);
  for (const t of pool) { r -= t.weight; if (r < 0) return t; }
  return pool[0];
}

export function regionName(c, text) {
  if (!c.regions) return '';
  return c.regions[text.split(/[ •]/)[0]] || '';
}
