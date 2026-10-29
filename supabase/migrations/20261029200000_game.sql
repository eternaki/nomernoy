-- Номерной: вся экономика живёт здесь. Клиент только читает таблицы и вызывает функции.
-- Числа аренды (0.5%/ч, 24 ч), бонуса, комиссии (5%) и наград коллекций совпадают с supabase/functions/_shared/plates.js.

-- ---------- таблицы ----------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nick text not null unique check (char_length(nick) between 3 and 20),
  balance bigint not null default 5000 check (balance >= 0),
  pity int not null default 0,
  daily_last date,
  daily_streak int not null default 0,
  rent_at timestamptz not null default now(),
  rent_pending bigint not null default 0,
  created_at timestamptz not null default now()
);

create table public.plates (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references public.profiles on delete cascade,
  country text not null,
  text text not null,
  tier text not null,
  value int not null,
  created_at timestamptz not null default now(),
  unique (country, text) -- каждый номер существует в одном экземпляре
);
create index plates_owner_idx on public.plates (owner);

create table public.listings (
  plate_id uuid primary key references public.plates on delete cascade,
  seller uuid not null references public.profiles on delete cascade,
  price bigint not null check (price between 1 and 100000000),
  created_at timestamptz not null default now()
);

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references public.profiles on delete cascade,
  to_id uuid not null references public.profiles on delete cascade,
  give_plates uuid[] not null default '{}',
  want_plates uuid[] not null default '{}',
  give_money bigint not null default 0 check (give_money >= 0),
  want_money bigint not null default 0 check (want_money >= 0),
  status text not null default 'open' check (status in ('open', 'accepted', 'declined', 'cancelled', 'failed')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);
create index offers_to_idx on public.offers (to_id, status);
create index offers_from_idx on public.offers (from_id, status);

create table public.claims (
  user_id uuid not null references public.profiles on delete cascade,
  collection text not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, collection)
);

-- ---------- доступ: читать можно, писать только через функции ----------
alter table public.profiles enable row level security;
alter table public.plates enable row level security;
alter table public.listings enable row level security;
alter table public.offers enable row level security;
alter table public.claims enable row level security;
create policy "все видят профили" on public.profiles for select using (true);
create policy "все видят номера" on public.plates for select using (true);
create policy "все видят рынок" on public.listings for select using (true);
create policy "свои обмены" on public.offers for select using (auth.uid() in (from_id, to_id));
create policy "свои коллекции" on public.claims for select using (auth.uid() = user_id);

-- ---------- новый игрок ----------
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  loop
    begin
      insert into profiles (id, nick) values (new.id, 'Игрок' || (10000 + floor(random() * 90000))::int);
      exit;
    exception when unique_violation then
      -- ник совпал, пробуем другой
    end;
  end loop;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- служебные ----------
create function public._uid() returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null then raise exception 'Нужно войти'; end if;
  return auth.uid();
end $$;

-- Торговать могут только вошедшие через Google или Telegram, не гости
create function public._member() returns uuid language plpgsql stable as $$
begin
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Торговать можно после входа через Google или Telegram';
  end if;
  return public._uid();
end $$;

-- Начисляет аренду за время с прошлого начисления. Вызывается перед любым изменением гаража,
-- чтобы аренда считалась от того, что реально стояло в гараже.
create function public._accrue(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t timestamptz; total bigint;
begin
  select rent_at into t from profiles where id = p_uid for update;
  select coalesce(sum(value), 0) into total from plates where owner = p_uid;
  update profiles
     set rent_pending = rent_pending + floor(total * 0.005 * least(extract(epoch from now() - t) / 3600, 24)),
         rent_at = now()
   where id = p_uid;
end $$;

-- ---------- игрок ----------
create function public.set_nick(p_nick text) returns text
language plpgsql security definer set search_path = public as $$
declare n text := btrim(p_nick);
begin
  if char_length(n) not between 3 and 20 then raise exception 'Ник — от 3 до 20 символов'; end if;
  if n ~ '[<>&"''`\\]' or n ~ '[[:cntrl:]]' then raise exception 'В нике есть недопустимые символы'; end if;
  update profiles set nick = n where id = _uid();
  return n;
exception when unique_violation then
  raise exception 'Этот ник уже занят';
end $$;

create function public.claim_rent() returns bigint
language plpgsql security definer set search_path = public as $$
declare uid uuid := _uid(); amt bigint;
begin
  perform _accrue(uid);
  select rent_pending into amt from profiles where id = uid;
  update profiles set balance = balance + amt, rent_pending = 0 where id = uid;
  return amt;
end $$;

create function public.claim_daily() returns json
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := _uid();
  today date := (now() at time zone 'Europe/Kyiv')::date;
  p profiles;
  s int;
  amt bigint;
begin
  select * into p from profiles where id = uid for update;
  if p.daily_last = today then raise exception 'Бонус уже получен сегодня'; end if;
  s := case when p.daily_last = today - 1 then p.daily_streak + 1 else 1 end;
  amt := least(500 + (s - 1) * 250, 2000);
  update profiles set balance = balance + amt, daily_last = today, daily_streak = s where id = uid;
  return json_build_object('amount', amt, 'streak', s);
end $$;

-- Продажа «государству» по номинальной стоимости (одного номера или пачки)
create function public.sell_plates(p_ids uuid[]) returns bigint
language plpgsql security definer set search_path = public as $$
declare uid uuid := _uid(); total bigint;
begin
  perform _accrue(uid);
  with d as (
    delete from plates p
     where p.id = any(p_ids) and p.owner = uid
       and not exists (select 1 from listings l where l.plate_id = p.id)
    returning p.value
  )
  select coalesce(sum(value), 0) into total from d;
  update profiles set balance = balance + total where id = uid;
  return total;
end $$;

create function public.claim_collection(p_id text) returns bigint
language plpgsql security definer set search_path = public as $$
declare uid uuid := _uid(); reward bigint; ok boolean;
begin
  reward := case p_id
    when 'kyiv' then 500 when 'ua10' then 1500 when 'euro' then 2000 when 'world' then 6000
    when 'garage30' then 1000 when 'rich' then 2000 when 'legend' then 2500 when 'myth' then 8000 end;
  if reward is null then raise exception 'Нет такой коллекции'; end if;
  ok := case p_id
    when 'kyiv' then
      exists (select 1 from plates where owner = uid and country = 'ua' and tier <> 'mythic' and split_part(text, ' ', 1) = 'AA')
      and exists (select 1 from plates where owner = uid and country = 'ua' and tier <> 'mythic' and split_part(text, ' ', 1) = 'KA')
    when 'ua10' then
      (select count(distinct split_part(text, ' ', 1)) from plates where owner = uid and country = 'ua' and tier <> 'mythic') >= 10
    when 'euro' then
      (select count(distinct country) from plates where owner = uid and country in ('pl', 'pt', 'nl', 'it', 'fr', 'de')) = 6
    when 'world' then (select count(distinct country) from plates where owner = uid) >= 11
    when 'garage30' then (select count(*) from plates where owner = uid) >= 30
    when 'rich' then (select coalesce(sum(value), 0) from plates where owner = uid) >= 20000
    when 'legend' then exists (select 1 from plates where owner = uid and tier = 'legendary')
    when 'myth' then exists (select 1 from plates where owner = uid and tier = 'mythic')
  end;
  if not ok then raise exception 'Условие коллекции ещё не выполнено'; end if;
  insert into claims (user_id, collection) values (uid, p_id);
  update profiles set balance = balance + reward where id = uid;
  return reward;
exception when unique_violation then
  raise exception 'Награда за эту коллекцию уже получена';
end $$;

-- ---------- рынок ----------
create function public.list_plate(p_plate uuid, p_price bigint) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _member();
begin
  if p_price is null or p_price not between 1 and 100000000 then raise exception 'Цена — от 1 до 100 000 000 ₴'; end if;
  if not exists (select 1 from plates where id = p_plate and owner = uid) then raise exception 'Это не твой номер'; end if;
  insert into listings (plate_id, seller, price) values (p_plate, uid, p_price)
    on conflict (plate_id) do update set price = excluded.price;
end $$;

create function public.unlist_plate(p_plate uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from listings where plate_id = p_plate and seller = _uid();
end $$;

create function public.buy_listing(p_plate uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare uid uuid := _member(); l listings;
begin
  select * into l from listings where plate_id = p_plate for update;
  if not found then raise exception 'Номер уже продан или снят с продажи'; end if;
  if l.seller = uid then raise exception 'Это твой номер'; end if;
  perform _accrue(uid);
  perform _accrue(l.seller);
  update profiles set balance = balance - l.price where id = uid and balance >= l.price;
  if not found then raise exception 'Не хватает денег'; end if;
  update profiles set balance = balance + l.price - ceil(l.price * 0.05) where id = l.seller;
  update plates set owner = uid where id = p_plate;
  delete from listings where plate_id = p_plate;
  return l.price;
end $$;

-- ---------- обмены ----------
create function public.create_offer(p_to uuid, p_give uuid[], p_want uuid[], p_give_money bigint, p_want_money bigint) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := _member(); oid uuid;
begin
  p_give := coalesce(p_give, '{}'); p_want := coalesce(p_want, '{}');
  p_give_money := coalesce(p_give_money, 0); p_want_money := coalesce(p_want_money, 0);
  if p_to = uid then raise exception 'Нельзя меняться с самим собой'; end if;
  if not exists (select 1 from auth.users where id = p_to and not is_anonymous) then
    raise exception 'Этот игрок — гость, ему пока нельзя предлагать обмен';
  end if;
  if p_give_money < 0 or p_want_money < 0 then raise exception 'Сумма не может быть отрицательной'; end if;
  if cardinality(p_give) + cardinality(p_want) = 0 and p_give_money = 0 and p_want_money = 0 then
    raise exception 'Пустое предложение';
  end if;
  if cardinality(p_give) > 10 or cardinality(p_want) > 10 then raise exception 'Не больше 10 номеров с каждой стороны'; end if;
  if (select count(*) from plates where id = any(p_give) and owner = uid) <> cardinality(p_give) then
    raise exception 'Отдавать можно только свои номера';
  end if;
  if (select count(*) from plates where id = any(p_want) and owner = p_to) <> cardinality(p_want) then
    raise exception 'Можно просить только номера этого игрока';
  end if;
  if (select balance from profiles where id = uid) < p_give_money then raise exception 'Не хватает денег'; end if;
  insert into offers (from_id, to_id, give_plates, want_plates, give_money, want_money)
    values (uid, p_to, p_give, p_want, p_give_money, p_want_money) returning id into oid;
  return oid;
end $$;

-- Ответ на обмен. Всё ещё раз проверяется в момент принятия: номера могли продать, деньги потратить.
create function public.respond_offer(p_offer uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare uid uuid := _uid(); o offers;
begin
  select * into o from offers where id = p_offer for update;
  if not found or o.to_id <> uid or o.status <> 'open' then raise exception 'Предложение уже неактуально'; end if;
  if not p_accept then
    update offers set status = 'declined' where id = p_offer;
    return 'declined';
  end if;
  perform _member();
  if (select count(*) from plates p where p.id = any(o.give_plates) and p.owner = o.from_id
        and not exists (select 1 from listings l where l.plate_id = p.id)) <> cardinality(o.give_plates)
     or (select count(*) from plates p where p.id = any(o.want_plates) and p.owner = o.to_id
        and not exists (select 1 from listings l where l.plate_id = p.id)) <> cardinality(o.want_plates)
     or (select balance from profiles where id = o.from_id) < o.give_money
     or (select balance from profiles where id = o.to_id) < o.want_money then
    update offers set status = 'failed' where id = p_offer;
    return 'failed';
  end if;
  perform _accrue(o.from_id);
  perform _accrue(o.to_id);
  update profiles set balance = balance - o.give_money + o.want_money where id = o.from_id;
  update profiles set balance = balance - o.want_money + o.give_money where id = o.to_id;
  update plates set owner = o.to_id where id = any(o.give_plates);
  update plates set owner = o.from_id where id = any(o.want_plates);
  update offers set status = 'accepted' where id = p_offer;
  return 'accepted';
end $$;

create function public.cancel_offer(p_offer uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update offers set status = 'cancelled' where id = p_offer and from_id = _uid() and status = 'open';
end $$;

create function public.leaderboard() returns table (id uuid, nick text, plates bigint, worth bigint)
language sql stable security definer set search_path = public as $$
  select p.id, p.nick, count(pl.id), coalesce(sum(pl.value), 0)
    from profiles p join plates pl on pl.owner = p.id
   group by p.id
   order by 4 desc
   limit 50;
$$;

-- ---------- вызываются только серверными функциями (spin, contract, tg-auth) ----------
create function public.commit_spin(p_uid uuid, p_country text, p_price bigint, p_tier text, p_text text, p_value int, p_pity int) returns json
language plpgsql security definer set search_path = public as $$
declare pid uuid; bal bigint;
begin
  perform _accrue(p_uid);
  update profiles set balance = balance - p_price, pity = p_pity
   where id = p_uid and balance >= p_price returning balance into bal;
  if not found then raise exception 'Не хватает денег'; end if;
  insert into plates (owner, country, text, tier, value) values (p_uid, p_country, p_text, p_tier, p_value) returning id into pid;
  return json_build_object('id', pid, 'balance', bal);
end $$;

create function public.commit_contract(p_uid uuid, p_ids uuid[], p_tier_in text, p_country text, p_text text, p_tier text, p_value int) returns uuid
language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  if cardinality(p_ids) <> 10 then raise exception 'Нужно ровно 10 номеров'; end if;
  if (select count(*) from plates p where p.id = any(p_ids) and p.owner = p_uid and p.tier = p_tier_in
        and not exists (select 1 from listings l where l.plate_id = p.id)) <> 10 then
    raise exception 'Нужно 10 своих номеров одной редкости, не выставленных на рынок';
  end if;
  perform _accrue(p_uid);
  delete from plates where id = any(p_ids);
  insert into plates (owner, country, text, tier, value) values (p_uid, p_country, p_text, p_tier, p_value) returning id into pid;
  return pid;
end $$;

-- Гость вошёл через Telegram новым аккаунтом — переносим его прогресс
create function public.merge_guest(p_old uuid, p_new uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update profiles n
     set balance = o.balance, pity = o.pity, daily_last = o.daily_last, daily_streak = o.daily_streak,
         rent_at = o.rent_at, rent_pending = o.rent_pending
    from profiles o
   where n.id = p_new and o.id = p_old;
  update plates set owner = p_new where owner = p_old;
  update listings set seller = p_new where seller = p_old;
  insert into claims (user_id, collection, claimed_at)
    select p_new, collection, claimed_at from claims where user_id = p_old
    on conflict do nothing;
  delete from profiles where id = p_old;
end $$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public._accrue(uuid) from public, anon, authenticated;
revoke execute on function public.commit_spin(uuid, text, bigint, text, text, int, int) from public, anon, authenticated;
revoke execute on function public.commit_contract(uuid, uuid[], text, text, text, text, int) from public, anon, authenticated;
revoke execute on function public.merge_guest(uuid, uuid) from public, anon, authenticated;

-- явные права, не полагаемся на настройки по умолчанию
grant usage on schema public to anon, authenticated, service_role;
grant select on public.profiles, public.plates, public.listings, public.offers, public.claims to anon, authenticated;
grant all on public.profiles, public.plates, public.listings, public.offers, public.claims to service_role;
grant execute on function
  public.set_nick(text), public.claim_rent(), public.claim_daily(), public.sell_plates(uuid[]),
  public.claim_collection(text), public.list_plate(uuid, bigint), public.unlist_plate(uuid),
  public.buy_listing(uuid), public.create_offer(uuid, uuid[], uuid[], bigint, bigint),
  public.respond_offer(uuid, boolean), public.cancel_offer(uuid), public.leaderboard()
  to anon, authenticated;
grant execute on function
  public.commit_spin(uuid, text, bigint, text, text, int, int),
  public.commit_contract(uuid, uuid[], text, text, text, text, int),
  public.merge_guest(uuid, uuid)
  to service_role;
