-- Исправления по ревью безопасности: гонки при передаче номеров, гарант при параллельных крутках,
-- надёжная привязка Telegram-аккаунтов.

-- ---------- Telegram: какой аккаунт принадлежит какому tg_id. Пишет только сервер ----------
create table public.tg_accounts (
  tg_id bigint primary key,
  user_id uuid not null unique references auth.users on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.tg_accounts enable row level security; -- политик нет: читать и писать может только service_role
revoke all on public.tg_accounts from anon, authenticated;
grant all on public.tg_accounts to service_role;

-- ---------- рынок: номер блокируется, продаётся только если всё ещё у продавца ----------
create or replace function public.list_plate(p_plate uuid, p_price bigint) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := _member();
begin
  if p_price is null or p_price not between 1 and 100000000 then raise exception 'Цена — от 1 до 100 000 000 ₴'; end if;
  perform 1 from plates where id = p_plate and owner = uid for update;
  if not found then raise exception 'Это не твой номер'; end if;
  insert into listings (plate_id, seller, price) values (p_plate, uid, p_price)
    on conflict (plate_id) do update set price = excluded.price;
end $$;

create or replace function public.buy_listing(p_plate uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare uid uuid := _member(); l listings;
begin
  select * into l from listings where plate_id = p_plate for update;
  if not found then raise exception 'Номер уже продан или снят с продажи'; end if;
  if l.seller = uid then raise exception 'Это твой номер'; end if;
  perform 1 from plates where id = p_plate and owner = l.seller for update;
  if not found then raise exception 'Номер уже недоступен'; end if;
  perform _accrue(uid);
  perform _accrue(l.seller);
  update profiles set balance = balance - l.price where id = uid and balance >= l.price;
  if not found then raise exception 'Не хватает денег'; end if;
  update profiles set balance = balance + l.price - ceil(l.price * 0.05) where id = l.seller;
  update plates set owner = uid where id = p_plate;
  delete from listings where plate_id = p_plate;
  return l.price;
end $$;

-- ---------- обмен: блокируем номера до проверок, снимаем с рынка всё переданное ----------
create or replace function public.respond_offer(p_offer uuid, p_accept boolean) returns text
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
  perform 1 from plates where id = any(o.give_plates || o.want_plates) for update;
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
  delete from listings where plate_id = any(o.give_plates || o.want_plates);
  update offers set status = 'accepted' where id = p_offer;
  return 'accepted';
end $$;

-- ---------- контракт: блокируем номера, удаляем только свои ----------
create or replace function public.commit_contract(p_uid uuid, p_ids uuid[], p_tier_in text, p_country text, p_text text, p_tier text, p_value int) returns uuid
language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  if cardinality(p_ids) <> 10 then raise exception 'Нужно ровно 10 номеров'; end if;
  perform 1 from plates where id = any(p_ids) for update;
  if (select count(*) from plates p where p.id = any(p_ids) and p.owner = p_uid and p.tier = p_tier_in
        and not exists (select 1 from listings l where l.plate_id = p.id)) <> 10 then
    raise exception 'Нужно 10 своих номеров одной редкости, не выставленных на рынок';
  end if;
  perform _accrue(p_uid);
  delete from plates where id = any(p_ids) and owner = p_uid;
  insert into plates (owner, country, text, tier, value) values (p_uid, p_country, p_text, p_tier, p_value) returning id into pid;
  return pid;
end $$;

-- ---------- крутка: гарант считается от того значения, которое видел сервер при броске ----------
-- Если параллельная крутка успела поменять счётчик — ошибка, функция spin бросит заново.
drop function public.commit_spin(uuid, text, bigint, text, text, int, int);
create function public.commit_spin(p_uid uuid, p_country text, p_price bigint, p_tier text, p_text text, p_value int, p_pity int, p_prev_pity int) returns json
language plpgsql security definer set search_path = public as $$
declare pid uuid; bal bigint; cur int;
begin
  perform _accrue(p_uid);
  select pity into cur from profiles where id = p_uid for update;
  if cur is distinct from p_prev_pity then raise exception 'Счётчик гаранта изменился' using errcode = '40001'; end if;
  update profiles set balance = balance - p_price, pity = p_pity
   where id = p_uid and balance >= p_price returning balance into bal;
  if not found then raise exception 'Не хватает денег'; end if;
  insert into plates (owner, country, text, tier, value) values (p_uid, p_country, p_text, p_tier, p_value) returning id into pid;
  return json_build_object('id', pid, 'balance', bal);
end $$;
revoke execute on function public.commit_spin(uuid, text, bigint, text, text, int, int, int) from public, anon, authenticated;
grant execute on function public.commit_spin(uuid, text, bigint, text, text, int, int, int) to service_role;
