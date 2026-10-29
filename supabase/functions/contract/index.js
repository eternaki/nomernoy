// Контракт: 10 номеров одной редкости → 1 номер следующей редкости,
// страна — одна из стран отданных номеров.
import { countryOf, tierIdx, TIERS, pick } from '../_shared/plates.js';
import { admin, json, handler, issuePlate } from '../_shared/server.js';

Deno.serve(handler(async ({ user, body }) => {
  if (!user) return json({ error: 'Нужно войти' }, 401);
  const ids = [...new Set(body.ids || [])];
  if (ids.length !== 10) return json({ error: 'Нужно ровно 10 разных номеров' }, 400);

  const { data: plates } = await admin.from('plates').select('id, owner, country, tier').in('id', ids);
  if (plates?.length !== 10 || plates.some(p => p.owner !== user.id)) return json({ error: 'Это не твои номера' }, 400);
  const tierIn = plates[0].tier;
  if (plates.some(p => p.tier !== tierIn)) return json({ error: 'Все 10 номеров должны быть одной редкости' }, 400);
  if (tierIn === 'mythic') return json({ error: 'Мифические номера в контракт не идут' }, 400);

  const c = countryOf(pick(plates).country);
  const res = await issuePlate(c, TIERS[tierIdx(tierIn) + 1].id, (text, tier, value) => admin.rpc('commit_contract', {
    p_uid: user.id, p_ids: ids, p_tier_in: tierIn, p_country: c.id, p_text: text, p_tier: tier, p_value: value,
  }));
  return json({ item: { id: res.data, c: c.id, text: res.text, tier: res.tier, value: res.value } });
}));
