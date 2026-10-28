-- Vox: the three tables, with Row Level Security.
-- Every row belongs to one user. A user can only read and write their own rows.
-- Ids are made on the phone, so inserts always send their own id.
-- Run once in the Supabase dashboard: SQL Editor > New query > paste > Run.

-- Keeps updated_at for rows changed from the web app later. The phone sends its own.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

-- Notes tree: items and notes.
create table public.nodes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  parent_id uuid,
  kind text not null check (kind in ('item', 'note')),
  title text not null default '',
  body text,
  status text check (status in ('todo', 'doing', 'done')),
  view text check (view in ('list', 'checklist', 'board', 'folder')),
  color text,
  column_type text check (column_type in ('todo', 'doing', 'done')),
  details jsonb,
  due_at timestamptz,
  estimate_minutes int check (estimate_minutes >= 0),
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create index nodes_user_updated on public.nodes (user_id, updated_at);
create index nodes_parent on public.nodes (parent_id);

create trigger nodes_touch before update on public.nodes
  for each row execute function public.touch_updated_at();

-- Reminders and alarms.
create table public.reminders (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  node_id uuid,
  title text not null default '',
  fire_at timestamptz not null,
  kind text not null check (kind in ('reminder', 'alarm')),
  repeat_rule text,
  done boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create index reminders_user_updated on public.reminders (user_id, updated_at);

create trigger reminders_touch before update on public.reminders
  for each row execute function public.touch_updated_at();

-- Every applied command, with what undoes it.
create table public.action_log (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  transcript text not null default '',
  actions jsonb not null default '[]',
  inverse jsonb not null default '[]',
  summary text not null default '',
  undone boolean not null default false
);

create index action_log_user_created on public.action_log (user_id, created_at);

-- Row Level Security: on for every table, own rows only.
alter table public.nodes enable row level security;
alter table public.reminders enable row level security;
alter table public.action_log enable row level security;

create policy "Own nodes" on public.nodes
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Own reminders" on public.reminders
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Own action log" on public.action_log
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
