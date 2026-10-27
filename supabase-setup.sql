-- Run this once in Supabase: SQL Editor > New query > paste > Run

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  email text, name text,
  role text not null default 'staff' check (role in ('owner','staff')),
  status text not null default 'pending' check (status in ('pending','active','suspended')),
  created_at timestamptz default now()
);
create table ops (
  id bigint generated always as identity primary key,
  user_id uuid default auth.uid(),
  who text, kind text not null, payload jsonb not null,
  created_at timestamptz default now()
);
alter table profiles enable row level security;
alter table ops enable row level security;

create function is_owner() returns boolean language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and role='owner' and status='active') $$;
create function is_active() returns boolean language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and status='active') $$;

create policy "read own profile or owner reads all" on profiles for select using (id=auth.uid() or is_owner());
create policy "owner updates profiles" on profiles for update using (is_owner());
create policy "active users read ops" on ops for select using (is_active());
create policy "active users add ops" on ops for insert with check (
  is_active() and user_id=auth.uid() and (kind not in ('undo','set','svcdel') or is_owner())
);

create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as
$$ begin insert into profiles(id,email,name) values (new.id,new.email,split_part(new.email,'@',1)); return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

alter publication supabase_realtime add table ops;

-- AFTER the owner (Wapuri) has created her account in the app, run this with her email:
-- update profiles set role='owner', status='active' where email='WAPURI_EMAIL_HERE';
