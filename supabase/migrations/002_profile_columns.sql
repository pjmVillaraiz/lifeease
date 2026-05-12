alter table public.users add column if not exists display_name text;
alter table public.users add column if not exists phone text;
alter table public.users add column if not exists birthdate text;
alter table public.users add column if not exists medical_conditions text;
alter table public.users add column if not exists updated_at timestamptz default now();
