-- DukanDar update 2: bills with many items, repair lines, discounts,
-- shop phone / address, and years of history.
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run.
-- (Safe to run again; it only adds what is missing.)

-- ---- shop phone and address (printed on bills)
alter table public.shops add column if not exists phone text not null default '';
alter table public.shops add column if not exists address text not null default '';

-- New shops give their phone and address when they register.
drop function if exists public.create_shop(text, text);
create or replace function public.create_shop(
  p_shop_name text, p_display_name text,
  p_phone text default '', p_address text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if exists (select 1 from public.shop_members where user_id = auth.uid()) then
    raise exception 'this account already has a shop';
  end if;
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.shops where code = v_code);
  end loop;
  insert into public.shops(name, code, phone, address)
    values (p_shop_name, v_code, coalesce(p_phone, ''), coalesce(p_address, ''))
    returning id into v_id;
  insert into public.shop_members(user_id, shop_id, role, display_name, active)
    values (auth.uid(), v_id, 'owner', p_display_name, true);
  return v_id;
end;
$$;
revoke all on function public.create_shop(text, text, text, text) from public, anon;
grant execute on function public.create_shop(text, text, text, text) to authenticated;

-- The owner can change the shop's name, phone and address (and nothing else,
-- so nobody can extend their own subscription).
create or replace function public.update_shop_profile(
  p_name text, p_phone text, p_address text)
returns void language plpgsql security definer set search_path = public as $$
declare v_shop uuid;
begin
  v_shop := public.owner_shop_id();
  if v_shop is null then
    raise exception 'only the shop owner can do this';
  end if;
  update public.shops
    set name = coalesce(nullif(trim(p_name), ''), name),
        phone = coalesce(p_phone, ''),
        address = coalesce(p_address, '')
    where id = v_shop;
end;
$$;
revoke all on function public.update_shop_profile(text, text, text) from public, anon;
grant execute on function public.update_shop_profile(text, text, text) to authenticated;

-- ---- sales lines: which bill they belong to, the printed price, service name
alter table public.sales add column if not exists bill_id text not null default '';
alter table public.sales add column if not exists list_price double precision;
alter table public.sales add column if not exists item_name text not null default '';
create index if not exists sales_bill_idx on public.sales (bill_id);

-- ---- bills
create table if not exists public.bills (
  id text primary key,
  shop_id uuid not null,
  bill_no text not null,
  customer text,
  phone text,
  note text,
  discount double precision not null default 0,
  total double precision not null default 0,
  credit_id text not null default '',
  billed_at text not null,
  created_by text,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

alter table public.bills enable row level security;
drop policy if exists shop_read on public.bills;
drop policy if exists shop_insert on public.bills;
drop policy if exists shop_update on public.bills;
create policy shop_read on public.bills for select using (shop_id = public.my_shop_id());
create policy shop_insert on public.bills for insert with check (shop_id = public.my_shop_id());
create policy shop_update on public.bills for update
  using (shop_id = public.my_shop_id()) with check (shop_id = public.my_shop_id());
drop trigger if exists touch_server_ts on public.bills;
create trigger touch_server_ts before insert or update on public.bills
  for each row execute function public.touch_server_ts();
create index if not exists bills_sync_idx on public.bills (shop_id, server_ts);
create index if not exists bills_at_idx on public.bills (shop_id, billed_at);
