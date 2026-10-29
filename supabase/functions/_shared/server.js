import { createClient } from 'npm:@supabase/supabase-js@2';
import { makePlate, valueFor, tierOf } from './plates.js';

export const admin = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
export const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// Обёртка: CORS, разбор тела, пользователь по токену, ошибки — в JSON
export function handler(fn) {
  return async req => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
    try {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const { data } = jwt ? await admin.auth.getUser(jwt) : { data: {} };
      const body = await req.json().catch(() => ({}));
      return await fn({ user: data?.user || null, body, jwt });
    } catch (e) {
      return json({ error: e.message || String(e) }, 400);
    }
  };
}

// Выдаёт новый номер страны нужной редкости и сохраняет его через commit(text, tier, value).
// Номер уникален на весь мир: если такой уже есть, генерируем заново.
// Мифические ограничены списком — когда все разобраны, выпадает легендарный.
export async function issuePlate(c, tierId, commit) {
  let tier = tierOf(tierId);
  let free = c.mythic;
  if (tier.id === 'mythic') {
    const { data } = await admin.from('plates').select('text').eq('country', c.id).eq('tier', 'mythic');
    const taken = new Set((data || []).map(r => r.text));
    free = c.mythic.filter(m => !taken.has(m));
    if (!free.length) tier = tierOf('legendary');
  }
  for (let i = 0; i < 30; i++) {
    const text = makePlate(c, tier.id, free);
    const value = valueFor(c, tier);
    const { data, error } = await commit(text, tier.id, value);
    if (!error) return { data, text, tier: tier.id, value };
    if (error.code !== '23505') throw Object.assign(new Error(error.message), { code: error.code });
  }
  throw new Error('Не удалось подобрать свободный номер, попробуй ещё раз');
}
