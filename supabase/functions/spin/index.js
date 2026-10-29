import { countryOf, spinPrice, rollTier, tierIdx, RARE_IDX, PITY } from '../_shared/plates.js';
import { admin, json, handler, issuePlate } from '../_shared/server.js';

Deno.serve(handler(async ({ user, body }) => {
  if (!user) return json({ error: 'Нужно войти' }, 401);
  const c = countryOf(body.country);
  if (!c) return json({ error: 'Нет такой страны' }, 400);

  const { data: prof } = await admin.from('profiles').select('pity, balance').eq('id', user.id).single();
  const price = spinPrice(c);
  if (!prof || prof.balance < price) return json({ error: 'Не хватает денег' }, 400);

  const rolled = rollTier(prof.pity >= PITY - 1 ? RARE_IDX : 0);
  const res = await issuePlate(c, rolled.id, (text, tier, value) => admin.rpc('commit_spin', {
    p_uid: user.id, p_country: c.id, p_price: price, p_tier: tier, p_text: text, p_value: value,
    p_pity: tierIdx(tier) >= RARE_IDX ? 0 : prof.pity + 1,
  }));
  return json({
    item: { id: res.data.id, c: c.id, text: res.text, tier: res.tier, value: res.value },
    balance: res.data.balance,
  });
}));
