create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  first_name text,
  last_name text,
  display_name text,
  phone text,
  birthdate text,
  medical_conditions text,
  role text default 'elderly_user',
  language text default 'en',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.users add column if not exists email text;
alter table public.users add column if not exists first_name text;
alter table public.users add column if not exists last_name text;
alter table public.users add column if not exists display_name text;
alter table public.users add column if not exists phone text;
alter table public.users add column if not exists birthdate text;
alter table public.users add column if not exists medical_conditions text;
alter table public.users add column if not exists updated_at timestamptz default now();

create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  description text,
  reminder_time timestamptz,
  category text default 'general',
  repeat_type text,
  priority text default 'normal',
  is_completed boolean default false,
  language text default 'en',
  sync_status text default 'synced',
  created_at timestamptz default now()
);

create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  reminder_id uuid references public.reminders(id) on delete cascade,
  rule_type text not null,
  constraint_severity text default 'soft',
  rule_payload jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists public.voice_transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  transcript text not null,
  language text default 'mixed',
  intent text,
  confidence numeric,
  audio_path text,
  created_at timestamptz default now()
);

create table if not exists public.translated_texts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  source_text text not null,
  translated_text text not null,
  source_language text,
  target_language text,
  created_at timestamptz default now()
);

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  phone text not null,
  relationship text,
  priority integer default 1,
  created_at timestamptz default now()
);

create table if not exists public.sus_evaluations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  score integer,
  rating text,
  feedback text,
  answers jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

alter table public.users enable row level security;
alter table public.reminders enable row level security;
alter table public.schedules enable row level security;
alter table public.voice_transcripts enable row level security;
alter table public.translated_texts enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.sus_evaluations enable row level security;

create policy "Users can read own profile" on public.users
  for select using (auth.uid() = id);
create policy "Users can update own profile" on public.users
  for update using (auth.uid() = id);
create policy "Users can insert own profile" on public.users
  for insert with check (auth.uid() = id);

create policy "Users own reminders" on public.reminders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users own schedules" on public.schedules
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users own transcripts" on public.voice_transcripts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users own translations" on public.translated_texts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users own emergency contacts" on public.emergency_contacts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users own SUS evaluations" on public.sus_evaluations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, first_name, last_name, display_name)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    coalesce(new.raw_user_meta_data->>'display_name', 'LifeEase User')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into storage.buckets (id, name, public)
values
  ('audio-recordings', 'audio-recordings', false),
  ('profile-images', 'profile-images', true)
on conflict (id) do nothing;

create policy "Users manage own audio recordings" on storage.objects
  for all using (
    bucket_id = 'audio-recordings'
    and auth.uid()::text = (storage.foldername(name))[1]
  ) with check (
    bucket_id = 'audio-recordings'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Users manage own profile images" on storage.objects
  for all using (
    bucket_id = 'profile-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  ) with check (
    bucket_id = 'profile-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
