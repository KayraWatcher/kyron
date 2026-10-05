-- ===========================================================================
-- KYRON App Update Config (FAZ 17)
-- ===========================================================================
-- Merkezi config: latest_version, minimum_version, download_url
-- Admin dashboard'dan güncellenir, anon ile okunur.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) APP CONFIG TABLOSU
-- ---------------------------------------------------------------------------

create table if not exists public.app_config (
  key   text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

-- Varsayılan değerler (admin dashboard'dan değiştirilebilir)
insert into public.app_config (key, value) values
  ('latest_version', '1.0.0'),
  ('minimum_version', '1.0.0'),
  ('download_url', 'https://kyronapp.pages.dev/')
on conflict (key) do nothing;

-- RLS: anon ve authenticated sadece okuyabilir
alter table public.app_config enable row level security;

drop policy if exists "anon_read_app_config" on public.app_config;
create policy "anon_read_app_config"
  on public.app_config
  for select
  to anon, authenticated
  using (true);

-- Admin yazabilir (service-role veya admin kullanıcısı)
drop policy if exists "admin_write_app_config" on public.app_config;
create policy "admin_write_app_config"
  on public.app_config
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Güncelleme zamanını otomatik güncelle
drop trigger if exists "app_config_updated_at" on public.app_config;
create trigger "app_config_updated_at"
  before update on public.app_config
  for each row
  execute function public.update_updated_at_column();

-- ===========================================================================
-- 2) TELEMETRY EVENT TÜRLERİNE UPDATE EKLE
-- ===========================================================================

-- app_events tablosundaki event_type constraint'ini güncelle
alter table public.app_events
  drop constraint if exists app_events_type_check;

alter table public.app_events
  add constraint app_events_type_check
  check (event_type in ('app_open','app_update','update_check','update_available','forced_update_shown','update_download_clicked'));

-- ===========================================================================
-- 3) TELEMETRY RPC YE UPDATE EVENT DESTEGI EKLE
-- ===========================================================================

create or replace function public.telemetry_ping(
  p_installation_id text,
  p_platform        text,
  p_app_version     text,
  p_event           text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Girdi dogrulama: gecersiz istekler sessizce yutulur
  if p_installation_id is null
     or char_length(p_installation_id) < 8
     or char_length(p_installation_id) > 64 then
    return;
  end if;
  if p_platform is null
     or p_platform not in ('android','ios','web','macos','windows','linux','other') then
    return;
  end if;
  if p_app_version is null or char_length(p_app_version) > 32 then
    return;
  end if;

  -- Kurulum kaydi: ilk acilista olustur, sonrakilerde last_seen + surum guncelle.
  insert into public.app_installations
    (installation_id, platform, app_version, first_seen_at, last_seen_at)
  values
    (p_installation_id, p_platform, p_app_version, now(), now())
  on conflict (installation_id) do update
    set last_seen_at = now(),
        app_version  = excluded.app_version,
        platform     = excluded.platform;

  -- Olay kaydi: gecerli event türlerindense ve 10 dk icinde tekrar yoksa kaydet
  if p_event in ('app_open','app_update','update_check','update_available','forced_update_shown','update_download_clicked') then
    if not exists (
      select 1
      from public.app_events e
      where e.installation_id = p_installation_id
        and e.event_type      = p_event
        and e.created_at      > now() - interval '10 minutes'
    ) then
      insert into public.app_events
        (installation_id, event_type, app_version, platform)
      values
        (p_installation_id, p_event, p_app_version, p_platform);
    end if;
  end if;
end;
$$;

grant execute on function public.telemetry_ping to anon, authenticated, service_role;