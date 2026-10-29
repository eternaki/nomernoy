# Номерной

Браузерная игра: крути автомобильные номера 11 стран, собирай редкие, торгуй с другими игроками.

**Играть:** https://eternaki.github.io/nomernoy/

- `index.html` — вся страница.
- `supabase/functions/_shared/plates.js` — правила номеров, общие для страницы и сервера.
- `supabase/migrations/` — база и вся экономика (баланс, аренда, бонус, рынок, обмены, коллекции).
- `supabase/functions/` — прокрутка, контракт, вход через Telegram.

## Включить вход через Google

1. [Google Cloud Console](https://console.cloud.google.com/) → создать проект → **APIs & Services → OAuth consent screen**: External, название «Номерной», свой email.
2. **Credentials → Create credentials → OAuth client ID** → Web application.
   В **Authorized redirect URIs** добавить `https://ijacsixgtvhhivpxnmzg.supabase.co/auth/v1/callback`.
3. Скопировать Client ID и Client Secret в [Supabase → Auth → Providers → Google](https://supabase.com/dashboard/project/ijacsixgtvhhivpxnmzg/auth/providers), включить, сохранить.

Кнопка «Войти через Google» в игре включится сама.

## Включить вход через Telegram

1. В Telegram написать [@BotFather](https://t.me/BotFather): `/newbot` → придумать имя и username бота → получить токен.
2. Там же `/setdomain` → выбрать бота → `eternaki.github.io`.
3. [Supabase → Edge Functions → Secrets](https://supabase.com/dashboard/project/ijacsixgtvhhivpxnmzg/functions/secrets): добавить `TELEGRAM_BOT_TOKEN` = токен бота.

Кнопка Telegram в игре появится сама — имя бота сервер узнаёт по токену.
