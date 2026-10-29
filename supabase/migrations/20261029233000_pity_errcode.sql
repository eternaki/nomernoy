-- 40001 PostgREST воспринимает как конфликт транзакции и повторяет сам — запрос зависает.
-- Свой код ошибки: функция spin поймает его и бросит заново.
create or replace function public.commit_spin(p_uid uuid, p_country text, p_price bigint, p_tier text, p_text text, p_value int, p_pity int, p_prev_pity int) returns json
language plpgsql security definer set search_path = public as $$
declare pid uuid; bal bigint; cur int;
begin
  perform _accrue(p_uid);
  select pity into cur from profiles where id = p_uid for update;
  if cur is distinct from p_prev_pity then raise exception 'Счётчик гаранта изменился' using errcode = 'NM001'; end if;
  update profiles set balance = balance - p_price, pity = p_pity
   where id = p_uid and balance >= p_price returning balance into bal;
  if not found then raise exception 'Не хватает денег'; end if;
  insert into plates (owner, country, text, tier, value) values (p_uid, p_country, p_text, p_tier, p_value) returning id into pid;
  return json_build_object('id', pid, 'balance', bal);
end $$;
