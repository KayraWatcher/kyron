-- ===========================================================================
-- APP CONFIG: latest_version / minimum_version -> 1.1.0
-- ===========================================================================
-- Neden: 20261004090000_telemetry.sql seed'i her iki degeri de '1.0.0' birakir.
-- 1.0.0+1 kurulu bir cihazda `current(1.0.0) >= latest(1.0.0)` oldugu icin
-- update_service.dart `upToDate` donuyor ve forced update ekrani hic acilmaz.
-- Gercek zorunlu guncelleme testi icin minimum deger 1.1.0'a cikarilmali.
--
-- NOT: Bu migration idempotenttir. Gecmis migration DEGISTIRILMEMISTIR; boylece
-- hem yeni hem eski kurulumlarda ayni sonuc uretir.
--
-- Uygulama: Supabase Dashboard -> SQL Editor -> bu dosyayi yapistir -> Run
-- (ya da `supabase db push`).
-- ===========================================================================

insert into public.app_config (key, value) values
  ('latest_version',  '1.1.0'),
  ('minimum_version', '1.1.0'),
  ('download_url',    'https://kyronapp.pages.dev/')
on conflict (key) do update
  set value      = excluded.value,
      updated_at = now();

-- --- Dogrulama (calistirdiktan sonra) -------------------------------------
-- select key, value, updated_at
--   from public.app_config
--  where key in ('latest_version', 'minimum_version', 'download_url')
--  order by key;
-- Beklenen: latest_version=1.1.0, minimum_version=1.1.0
--
-- Cevap: 1.0.0+1 cihazinda zorunlu guncelleme ekrani acilmali.
-- Gormuyorsa RLS'i anon roluyle dogrula:
-- set local role anon;
-- select key, value from public.app_config;   -- 3 satir donmeli
-- reset role;
