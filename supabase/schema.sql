-- DukanDar cloud schema. Run this once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Also turn OFF "Confirm email" in Authentication -> Providers -> Email.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- shops
create table if not exists public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  -- You (the developer) change this date after a shop pays you.
  active_until date not null default (current_date + 30),
  created_at timestamptz not null default now()
);

create table if not exists public.shop_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  role text not null check (role in ('owner', 'staff')),
  username text,
  display_name text not null default '',
  perms text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists shop_members_shop_idx on public.shop_members(shop_id);

-- ------------------------------------------------------- helper functions
-- The shop the signed-in user belongs to. Returns null when the member is
-- switched off OR the shop's "active_until" date has passed, so an unpaid
-- shop is cut off on the server too, not just in the app.
create or replace function public.my_shop_id() returns uuid
language sql stable security definer set search_path = public as $$
  select m.shop_id
  from public.shop_members m
  join public.shops s on s.id = m.shop_id
  where m.user_id = auth.uid() and m.active and s.active_until >= current_date
  limit 1;
$$;

create or replace function public.owner_shop_id() returns uuid
language sql stable security definer set search_path = public as $$
  select m.shop_id
  from public.shop_members m
  join public.shops s on s.id = m.shop_id
  where m.user_id = auth.uid() and m.role = 'owner' and m.active
    and s.active_until >= current_date
  limit 1;
$$;

create or replace function public.touch_server_ts() returns trigger
language plpgsql as $$
begin
  new.server_ts := clock_timestamp();
  return new;
end;
$$;

-- A new owner creates their shop (called by the app right after sign-up).
create or replace function public.create_shop(p_shop_name text, p_display_name text)
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
  insert into public.shops(name, code) values (p_shop_name, v_code) returning id into v_id;
  insert into public.shop_members(user_id, shop_id, role, display_name, active)
  values (auth.uid(), v_id, 'owner', p_display_name, true);
  return v_id;
end;
$$;

revoke all on function public.create_shop(text, text) from public, anon;
grant execute on function public.create_shop(text, text) to authenticated;

-- ------------------------------------------------------------ shop tables
alter table public.shops enable row level security;
alter table public.shop_members enable row level security;

drop policy if exists shops_read on public.shops;
create policy shops_read on public.shops for select
  using (id in (select shop_id from public.shop_members where user_id = auth.uid()));

drop policy if exists members_read on public.shop_members;
create policy members_read on public.shop_members for select
  using (user_id = auth.uid() or shop_id = public.owner_shop_id());

drop policy if exists members_insert on public.shop_members;
create policy members_insert on public.shop_members for insert
  with check (role = 'staff' and shop_id = public.owner_shop_id());

drop policy if exists members_update on public.shop_members;
create policy members_update on public.shop_members for update
  using (role = 'staff' and shop_id = public.owner_shop_id())
  with check (role = 'staff' and shop_id = public.owner_shop_id());

-- ------------------------------------------------------------ data tables
-- Same columns as the app's local database, plus server_ts used for syncing.
-- Rows are never hard-deleted: "deleted = 1" is a soft delete so it syncs.

create table if not exists public.products (
  id text primary key,
  shop_id uuid not null,
  name text not null,
  category text not null,
  subcategory text,
  brand text,
  model text,
  created_at text not null,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

create table if not exists public.batches (
  id text primary key,
  shop_id uuid not null,
  product_id text not null,
  qty integer not null,
  unit_cost double precision not null,
  serial text,
  purchased_at text not null,
  created_by text,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

create table if not exists public.sales (
  id text primary key,
  shop_id uuid not null,
  product_id text not null,
  qty integer not null,
  unit_price double precision not null,
  unit_cost double precision not null,
  extra_cost double precision not null default 0,
  customer text,
  note text,
  credit_id text,
  sold_at text not null,
  created_by text,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

create table if not exists public.credits (
  id text primary key,
  shop_id uuid not null,
  sale_id text,
  product_id text not null,
  product_name text,
  customer_name text not null,
  phone text,
  qty integer not null,
  total_due double precision not null,
  taken_at text not null,
  expected_date text not null,
  note text,
  created_by text,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

create table if not exists public.credit_payments (
  id text primary key,
  shop_id uuid not null,
  credit_id text not null,
  amount double precision not null,
  paid_at text not null,
  created_by text,
  updated_at text not null,
  deleted integer not null default 0,
  server_ts timestamptz not null default clock_timestamp()
);

do $$
declare t text;
begin
  foreach t in array array['products','batches','sales','credits','credit_payments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists shop_read on public.%I', t);
    execute format('drop policy if exists shop_insert on public.%I', t);
    execute format('drop policy if exists shop_update on public.%I', t);
    execute format('create policy shop_read on public.%I for select using (shop_id = public.my_shop_id())', t);
    execute format('create policy shop_insert on public.%I for insert with check (shop_id = public.my_shop_id())', t);
    execute format('create policy shop_update on public.%I for update using (shop_id = public.my_shop_id()) with check (shop_id = public.my_shop_id())', t);
    execute format('drop trigger if exists touch_server_ts on public.%I', t);
    execute format('create trigger touch_server_ts before insert or update on public.%I for each row execute function public.touch_server_ts()', t);
    execute format('create index if not exists %I on public.%I (shop_id, server_ts)', t || '_sync_idx', t);
  end loop;
end $$;
