// Вход через Telegram Login Widget.
// Проверяем подпись данных токеном бота, находим или создаём пользователя и отдаём одноразовый
// token_hash — страница обменивает его на сессию через supabase.auth.verifyOtp.
// Если до этого игрок был гостем и Telegram-аккаунт новый — переносим прогресс гостя.
import { admin, json, handler } from '../_shared/server.js';

const enc = new TextEncoder();
const hex = buf => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');

async function validTelegram(tg, botToken) {
  const check = Object.keys(tg).filter(k => k !== 'hash' && tg[k] != null).sort().map(k => `${k}=${tg[k]}`).join('\n');
  const secret = await crypto.subtle.digest('SHA-256', enc.encode(botToken));
  const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = hex(await crypto.subtle.sign('HMAC', key, enc.encode(check)));
  const fresh = Date.now() / 1000 - Number(tg.auth_date) < 86400;
  return sig === tg.hash && fresh;
}

let botName; // имя бота узнаём по токену, чтобы страница могла показать кнопку входа
async function getBotName(botToken) {
  if (botName === undefined) {
    const r = await fetch(`https://api.telegram.org/bot${botToken}/getMe`).then(r => r.json()).catch(() => null);
    botName = r?.result?.username || null;
  }
  return botName;
}

Deno.serve(handler(async ({ user: caller, body }) => {
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN');
  if (body.config) return json({ bot: botToken ? await getBotName(botToken) : null });
  if (!botToken) return json({ error: 'Вход через Telegram ещё не настроен' }, 400);
  const tg = body.tg;
  if (!tg?.id || !tg?.hash || !(await validTelegram(tg, botToken))) return json({ error: 'Telegram не подтвердил вход' }, 401);

  // Аккаунт ищем только по таблице tg_accounts, которую пишет сервер, — не по почте.
  // Почта со случайной частью: её нельзя заранее зарегистрировать, чтобы перехватить чужой вход.
  let email;
  const { data: known } = await admin.from('tg_accounts').select('user_id').eq('tg_id', tg.id).maybeSingle();
  if (known) {
    const { data, error } = await admin.auth.admin.getUserById(known.user_id);
    if (error || !data?.user?.email) return json({ error: 'Аккаунт не найден' }, 400);
    email = data.user.email;
  } else {
    email = `tg-${tg.id}-${crypto.randomUUID().slice(0, 12)}@telegram.example.com`;
    const { data: created, error } = await admin.auth.admin.createUser({
      email, email_confirm: true,
      app_metadata: { tg_id: tg.id },
      user_metadata: { name: [tg.first_name, tg.last_name].filter(Boolean).join(' '), username: tg.username },
    });
    if (error) return json({ error: error.message }, 400);
    const { error: mapErr } = await admin.from('tg_accounts').insert({ tg_id: tg.id, user_id: created.user.id });
    if (mapErr) { // параллельный вход уже создал аккаунт
      await admin.auth.admin.deleteUser(created.user.id);
      return json({ error: 'Попробуй войти ещё раз' }, 409);
    }
    if (caller?.is_anonymous) {
      const { error: mergeErr } = await admin.rpc('merge_guest', { p_old: caller.id, p_new: created.user.id });
      if (!mergeErr) await admin.auth.admin.deleteUser(caller.id);
    }
    const nick = (tg.username || tg.first_name || '').replace(/[<>&"'`\\]/g, '').slice(0, 20);
    if (nick.length >= 3) await admin.from('profiles').update({ nick }).eq('id', created.user.id); // занят — останется «ИгрокNNNNN»
  }

  const { data: link, error: linkErr } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  if (linkErr) return json({ error: linkErr.message }, 400);
  return json({ token_hash: link.properties.hashed_token });
}));
