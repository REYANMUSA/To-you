-- TO YOU — production Supabase foundation
-- Run once in Supabase SQL Editor. Browser uses anon key only.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text,
  visual_mode text not null default 'classic' check (visual_mode in ('classic','girl')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'CONNECTED' check(status in ('PENDING','CONNECTED','DISCONNECTED')),
  created_at timestamptz not null default now(),
  disconnected_at timestamptz,
  unique(user_id,partner_id), check(user_id<>partner_id)
);
create index if not exists connections_user_idx on public.connections(user_id,status);
create index if not exists connections_partner_idx on public.connections(partner_id,status);

create table if not exists public.connection_codes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  code text not null unique,
  expires_at timestamptz not null default (now()+interval '24 hours'),
  used_at timestamptz,
  used_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists codes_code_idx on public.connection_codes(code);

create table if not exists public.habits (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, frequency text not null default 'Daily', archived boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.habit_completions (
  id uuid primary key default gen_random_uuid(), habit_id uuid not null references public.habits(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade, completed_on date not null,
  created_at timestamptz not null default now(), unique(habit_id,completed_on)
);
create index if not exists habit_owner_idx on public.habits(owner_user_id);
create index if not exists habit_completion_owner_idx on public.habit_completions(owner_user_id,completed_on);

create table if not exists public.tasks (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, due_date date, archived boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.task_completions (
  id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade, completed_on date not null,
  created_at timestamptz not null default now(), unique(task_id,completed_on)
);

create table if not exists public.goals (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, description text default '', progress integer not null default 0 check(progress between 0 and 100),
  target_date date, status text not null default 'ACTIVE' check(status in ('ACTIVE','COMPLETED','ARCHIVED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.journey_events (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, event_date date not null, time_position text not null default 'past' check(time_position in ('past','present','future')),
  description text default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.journey_media (
  id uuid primary key default gen_random_uuid(), journey_event_id uuid not null references public.journey_events(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade, storage_path text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.shared_records (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid references public.connections(id) on delete cascade, record_type text not null, record_id uuid not null,
  created_at timestamptz not null default now()
);
create table if not exists public.shared_goals (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  connection_id uuid not null references public.connections(id) on delete cascade,
  title text not null, description text default '', progress integer not null default 0 check(progress between 0 and 100),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.need_signals (
  id uuid primary key default gen_random_uuid(), sender_user_id uuid not null references auth.users(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade, created_at timestamptz not null default now(), seen_at timestamptz
);

create table if not exists public.courses (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null, start_date date, target_date date, progress integer not null default 0 check(progress between 0 and 100),
  status text not null default 'IN_PROGRESS', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.notes (
  id uuid primary key, owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null, body text default '', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.reflections (
  id uuid primary key default gen_random_uuid(), owner_user_id uuid not null references auth.users(id) on delete cascade,
  reflection_date date not null, went_well text default '', improve text default '', grateful text default '', created_at timestamptz not null default now(), unique(owner_user_id,reflection_date)
);

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  visual_mode text not null default 'classic' check(visual_mode in ('classic','girl')),
  dark_mode boolean not null default false, notifications boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Helper: member of a connected pair
create or replace function public.is_connected_to(p_user uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.connections c where c.status='CONNECTED' and ((c.user_id=auth.uid() and c.partner_id=p_user) or (c.partner_id=auth.uid() and c.user_id=p_user)));
$$;

-- Auth profile bootstrap
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name,avatar_url) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.raw_user_meta_data->>'avatar_url') on conflict(id) do nothing;
  insert into public.user_settings(user_id) values(new.id) on conflict(user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Secure connection-code RPCs
create or replace function public.create_connection_code() returns text
language plpgsql security definer set search_path=public as $$
declare c text;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  c := 'TOYOU-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,4))||'-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,4));
  insert into public.connection_codes(owner_user_id,code) values(auth.uid(),c); return c;
end; $$;
revoke all on function public.create_connection_code() from public; grant execute on function public.create_connection_code() to authenticated;

create or replace function public.redeem_connection_code(p_code text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare row public.connection_codes%rowtype; cid uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into row from public.connection_codes where code=upper(trim(p_code)) and used_at is null and expires_at>now() for update;
  if not found then raise exception 'Code is invalid or expired'; end if;
  if row.owner_user_id=auth.uid() then raise exception 'You cannot connect to yourself'; end if;
  if exists(select 1 from public.connections where status='CONNECTED' and ((user_id=auth.uid() and partner_id=row.owner_user_id) or (partner_id=auth.uid() and user_id=row.owner_user_id))) then raise exception 'Already connected'; end if;
  insert into public.connections(user_id,partner_id,status) values(auth.uid(),row.owner_user_id,'CONNECTED') returning id into cid;
  insert into public.connections(user_id,partner_id,status) values(row.owner_user_id,auth.uid(),'CONNECTED') on conflict do nothing;
  update public.connection_codes set used_at=now(),used_by=auth.uid() where id=row.id;
  return jsonb_build_object('connection_id',cid,'partner_id',row.owner_user_id);
end; $$;
revoke all on function public.redeem_connection_code(text) from public; grant execute on function public.redeem_connection_code(text) to authenticated;

-- RLS: private records belong only to their owner. Connected profiles are visible; shared tables require explicit rows.
do $$ declare t text; begin
  foreach t in array array['profiles','user_settings','habits','habit_completions','tasks','task_completions','goals','journey_events','journey_media','courses','notes','reflections','connections','connection_codes','shared_records','shared_goals','need_signals'] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

-- Profiles/settings
 drop policy if exists profiles_select on public.profiles; create policy profiles_select on public.profiles for select using(id=auth.uid() or public.is_connected_to(id));
 drop policy if exists profiles_insert on public.profiles; create policy profiles_insert on public.profiles for insert with check(id=auth.uid());
 drop policy if exists profiles_update on public.profiles; create policy profiles_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
 drop policy if exists settings_all on public.user_settings; create policy settings_all on public.user_settings for all using(user_id=auth.uid()) with check(user_id=auth.uid());

-- Owner-only generic policies
 drop policy if exists habits_all on public.habits; create policy habits_all on public.habits for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists habit_completions_all on public.habit_completions; create policy habit_completions_all on public.habit_completions for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists tasks_all on public.tasks; create policy tasks_all on public.tasks for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists task_completions_all on public.task_completions; create policy task_completions_all on public.task_completions for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists goals_all on public.goals; create policy goals_all on public.goals for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists journey_events_all on public.journey_events; create policy journey_events_all on public.journey_events for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists journey_media_all on public.journey_media; create policy journey_media_all on public.journey_media for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists courses_all on public.courses; create policy courses_all on public.courses for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists notes_all on public.notes; create policy notes_all on public.notes for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists reflections_all on public.reflections; create policy reflections_all on public.reflections for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists connections_all on public.connections; create policy connections_all on public.connections for all using(user_id=auth.uid() or partner_id=auth.uid()) with check(user_id=auth.uid() or partner_id=auth.uid());
 drop policy if exists codes_owner on public.connection_codes; create policy codes_owner on public.connection_codes for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists shared_records_owner on public.shared_records; create policy shared_records_owner on public.shared_records for all using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
 drop policy if exists shared_goals_member on public.shared_goals; create policy shared_goals_member on public.shared_goals for all using(public.is_connected_to(owner_user_id)) with check(owner_user_id=auth.uid());
 drop policy if exists need_signals_member on public.need_signals; create policy need_signals_member on public.need_signals for select using(sender_user_id=auth.uid() or recipient_user_id=auth.uid());
 drop policy if exists need_signals_sender on public.need_signals; create policy need_signals_sender on public.need_signals for insert with check(sender_user_id=auth.uid() and public.is_connected_to(recipient_user_id));

-- Private photo bucket. Files live under <user_id>/...
insert into storage.buckets(id,name,public) values('journey-media','journey-media',false) on conflict(id) do nothing;
drop policy if exists journey_media_upload on storage.objects;
create policy journey_media_upload on storage.objects for insert to authenticated with check(bucket_id='journey-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists journey_media_read on storage.objects;
create policy journey_media_read on storage.objects for select to authenticated using(bucket_id='journey-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists journey_media_delete on storage.objects;
create policy journey_media_delete on storage.objects for delete to authenticated using(bucket_id='journey-media' and (storage.foldername(name))[1]=auth.uid()::text);


-- Us: shared Qur’an muraaja’ah and meaningful ayahs
create table if not exists public.quran_muraajaah_daily (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  quran_date date not null,
  target_pages integer not null default 3 check (target_pages = 3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(couple_id, quran_date)
);

create table if not exists public.quran_muraajaah_progress (
  couple_id uuid not null references public.couples(id) on delete cascade,
  quran_date date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  pages_completed integer not null default 0 check (pages_completed between 0 and 3),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (couple_id, quran_date, user_id)
);

create table if not exists public.quran_ayah_notes (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  surah text not null,
  ayah integer not null check (ayah > 0),
  arabic text not null,
  translation text not null,
  note text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.quran_muraajaah_daily enable row level security;
alter table public.quran_muraajaah_progress enable row level security;
alter table public.quran_ayah_notes enable row level security;

grant select, insert, update, delete on public.quran_muraajaah_daily to authenticated;
grant select, insert, update, delete on public.quran_muraajaah_progress to authenticated;
grant select, insert, update, delete on public.quran_ayah_notes to authenticated;

drop policy if exists quran_muraajaah_daily_member on public.quran_muraajaah_daily;
create policy quran_muraajaah_daily_member on public.quran_muraajaah_daily
for all to authenticated
using (exists (
  select 1 from public.couple_members cm
  where cm.couple_id = quran_muraajaah_daily.couple_id and cm.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.couple_members cm
  where cm.couple_id = quran_muraajaah_daily.couple_id and cm.user_id = (select auth.uid())
) and target_pages = 3);

drop policy if exists quran_muraajaah_progress_select on public.quran_muraajaah_progress;
create policy quran_muraajaah_progress_select on public.quran_muraajaah_progress
for select to authenticated
using (exists (
  select 1 from public.couple_members cm
  where cm.couple_id = quran_muraajaah_progress.couple_id and cm.user_id = (select auth.uid())
));

drop policy if exists quran_muraajaah_progress_insert on public.quran_muraajaah_progress;
create policy quran_muraajaah_progress_insert on public.quran_muraajaah_progress
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_muraajaah_progress.couple_id and cm.user_id = (select auth.uid())
  )
);

drop policy if exists quran_muraajaah_progress_update on public.quran_muraajaah_progress;
create policy quran_muraajaah_progress_update on public.quran_muraajaah_progress
for update to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_muraajaah_progress.couple_id and cm.user_id = (select auth.uid())
  )
)
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_muraajaah_progress.couple_id and cm.user_id = (select auth.uid())
  )
);

drop policy if exists quran_muraajaah_progress_delete on public.quran_muraajaah_progress;
create policy quran_muraajaah_progress_delete on public.quran_muraajaah_progress
for delete to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_muraajaah_progress.couple_id and cm.user_id = (select auth.uid())
  )
);

drop policy if exists quran_ayah_notes_select on public.quran_ayah_notes;
create policy quran_ayah_notes_select on public.quran_ayah_notes
for select to authenticated
using (exists (
  select 1 from public.couple_members cm
  where cm.couple_id = quran_ayah_notes.couple_id and cm.user_id = (select auth.uid())
));

drop policy if exists quran_ayah_notes_insert on public.quran_ayah_notes;
create policy quran_ayah_notes_insert on public.quran_ayah_notes
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_ayah_notes.couple_id and cm.user_id = (select auth.uid())
  )
);

drop policy if exists quran_ayah_notes_update on public.quran_ayah_notes;
create policy quran_ayah_notes_update on public.quran_ayah_notes
for update to authenticated
using (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_ayah_notes.couple_id and cm.user_id = (select auth.uid())
  )
)
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_ayah_notes.couple_id and cm.user_id = (select auth.uid())
  )
);

drop policy if exists quran_ayah_notes_delete on public.quran_ayah_notes;
create policy quran_ayah_notes_delete on public.quran_ayah_notes
for delete to authenticated
using (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.couple_members cm
    where cm.couple_id = quran_ayah_notes.couple_id and cm.user_id = (select auth.uid())
  )
);

create index if not exists quran_ayah_notes_couple_created_idx
  on public.quran_ayah_notes(couple_id, created_at desc);
create index if not exists quran_ayah_notes_created_by_idx
  on public.quran_ayah_notes(created_by);
create index if not exists quran_muraajaah_progress_user_idx
  on public.quran_muraajaah_progress(user_id);
