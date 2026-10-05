# KYRON — Supabase Telemetri Kurulumu

Bu klasör anonim kurulum telemetrisinin Supabase backend'ini içerir.
Kaynak kodda **service-role key yoktur**; yalnızca public anon anahtar
kullanılır (Flutter `--dart-define`, web `VITE_*`).

## Dosyalar

| Dosya | Amaç |
|---|---|
| `migrations/20261004090000_telemetry.sql` | Tablolar + RLS + `telemetry_ping` RPC + admin kurulumu |

## Kurulum adımları (manuel — Supabase hesabı/login gerektirir)

1. **Proje oluştur** — <https://supabase.com/dashboard> → New project.
2. **Migration'ı çalıştır** — Dashboard → SQL Editor →
   `migrations/20261004090000_telemetry.sql` dosyasını yapıştır → Run.
3. **Admin kullanıcısı oluştur** — Authentication → Users → Add user
   (email + şifre, *Auto Confirm* açık). Sonra SQL Editor'de:

   ```sql
   insert into public.admin_users (user_id)
   select id from auth.users where email = 'ADMIN_EMAIL'
   on conflict do nothing;
   ```

   Yetki **yalnızca veritabanında** tanımlıdır; web'de `if (email === ...)`
   gibi bir kontrol yoktur ve admin olmayan authenticated kullanıcılar
   RLS sayesinde tek satır bile okuyamaz.

4. **Anahtarları dağıt** (service-role ASLA):

   | Nereye | Ne |
   |---|---|
   | Flutter build | `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` |
   | Web local | `web/.env.local` (bkz. `web/.env.example`) |
   | Web GitHub Pages | Repo **Secrets**: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` |

## RLS / güvenlik doğrulama testleri (FAZ 15)

SQL Editor'de sırayla çalıştır (anahtarlar project'e göre değişir):

```sql
-- (A) anon rolü tabloyu OKUYAMAZ
set local role anon;
select count(*) from public.app_installations;  -- beklenti: 0 satır / permission denied
reset role;

-- (B) anon rolü tabloya DOĞRUDAN YAZAMAZ
set local role anon;
insert into public.app_installations (installation_id, platform, app_version)
values ('hack-1234-5678', 'android', '9.9.9');  -- beklenti: permission denied
reset role;

-- (C) anon RPC'yi ÇAĞIRABİLIR (telemetry akışı) ama okuma yine kapalı
select public.telemetry_ping('rls-test-0001', 'android', '1.0.0+1', 'app_open');
set local role anon;
select count(*) from public.app_installations
 where installation_id = 'rls-test-0001';        -- beklenti: 0 satır
reset role;

-- (D) authenticated ama ADMIN OLMAYAN kullanıcı okuyamaz
-- (dashboard'dan giriş yapıp bu sorguyu REST/Swagger üzerinden sorgula)
--   GET /rest/v1/app_installations  -> beklenti: [] (RLS)

-- (E) admin kullanıcısı okuyabilir
-- admin_users kaydından sonra giriş yap → Dashboard:
select count(*) from public.app_installations;  -- beklenti: gerçek sayı
```

## İstatistik tanımları (FAZ 9)

- **Toplam benzersiz kurulum** = `count(*)` over `app_installations`
  (`installation_id` UNIQUE).
- **Son 24 saat aktif** = `last_seen_at >= now() - interval '24 hours'`
- **Son 7 gün aktif** = `last_seen_at >= now() - interval '7 days'`
- **Son 30 gün aktif** = `last_seen_at >= now() - interval '30 days'`

## Gizlilik (FAZ 13)

Toplanan: anonim `installation_id` (uuid), `platform`, `app_version`,
`first_seen_at`, `last_seen_at`, `app_open`/`app_update` olayları.
Toplanmayan: isim, email, telefon, konum, IP, reklam ID, cihaz içeriği.
