# The core database — usage and how to interface with it

Every project made with UNAXIS gets **its own, fresh Supabase instance** (Postgres, Auth, REST, Storage,
Realtime, Studio behind one Kong gateway). It starts empty and is turned into a *core* by the migrations in
`supabase/migrations/`. Nothing in it comes from any other project.

UNAXIS decides where the instance runs and records that in `unaxis.project.json` under `stack.database`.
You never pick a host by hand.

## 1. Create it and keep it current

```bash
unaxis <env> project-stack plan                    # where would UNAXIS put it, and why (creates nothing)
unaxis <env> project-stack create <slug> --dir <project folder>   # pick host -> instance -> migrations -> wire the zone
unaxis <env> project-stack migrate <slug> --dir <project folder>  # apply new migrations only
```

`create` and `migrate` are idempotent. Each migration file runs in its own transaction and is recorded in
`public.schema_migrations`, so a failed file leaves nothing behind and a re-run applies only what is new.

## 2. Connecting

UNAXIS writes the connection for each wired zone to its stack env file (in its artifact store, never in git) and
layers it over the root `.env`. The variables the app reads:

| Variable | What it is | Where it may be used |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_URL` | API gateway the **servers** call (LAN address of the instance) | server only in practice |
| `NEXT_PUBLIC_SUPABASE_URL_BROWSER` / `SUPABASE_PUBLIC_URL` | public HTTPS URL the **browser** calls (`https://db.<slug>.<domain>`) | browser — needs its NPM host registered |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | the **anon** key. Public by design; RLS is what protects data | browser + server |
| `SUPABASE_SERVICE_ROLE_KEY` (`SERVICE_ROLE_KEY`) | the **service role** key. **Bypasses RLS.** | server only. Never in a client bundle |

Rule of thumb: if code runs in a browser it uses the anon key and is limited by the policies below; only trusted
server code uses the service role.

```bash
# REST: PostgREST, with the anon key
curl "$SUPABASE_URL/rest/v1/themes?select=id,name" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON"

# RPC: call a database function
curl -X POST "$SUPABASE_URL/rest/v1/rpc/get_translations" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d '{"p_locale":"es","p_namespaces":["common","auth"]}'
```

```ts
// supabase-js works as usual
import { createClient } from "@supabase/supabase-js";
const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL_BROWSER!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
```

## 3. What is in it

| Area | Tables |
|---|---|
| People | `profiles`, `roles`, `invites`, `team_members` |
| Zones (UNAXIS-managed sites) | `zones`, `zone_audit_events`, `zone_deployments`, `zone_endpoint_checks`, `zone_endpoint_status`, `zone_sync_runs` |
| Site content | `static_pages`, `pages`, `page_blocks`, `page_widgets`, `nav_items`, `landing_sections`, `landing_nav_items`, `homepage_content`, `hero_slides` |
| Banners | `site_banners`, `site_banner_groups`, `site_banner_group_items`, `site_banner_items` |
| Assets | `site_assets` (+ storage buckets below) |
| Theming | `themes`, `site_settings` |
| i18n | `languages`, `translations` |
| System | `notifications`, `admin_audit_log`, `schema_migrations` |

**Storage buckets** (all public-read, uploads via the service role): `avatars`, `attachments`, `hero-images`,
`site-assets`, `landing-assets`.

**Not included** (optional modules, added later as their own migrations): blog, commerce, analytics, documents,
messaging, mail. Nothing project-specific is in the core.

## 4. Security model

Every table in `public` has row level security enabled (`0002_security.sql`). This matters because Supabase
gives `anon` and `authenticated` full privileges on new tables — **a table without RLS is writable by anyone who
has the (public) anon key.**

| Who | Can |
|---|---|
| Anyone (anon) | Read public site content, active themes, languages, translations, site settings, **published** static pages |
| A signed-in user | Everything above, plus read/update **their own** profile and notifications |
| An admin (`profiles.role = 'admin'`, via `public.is_admin()`) | Manage all content, themes, settings, languages, translations, profiles, notifications; read the audit log |
| Service role | Everything (bypasses RLS). Server-side only |
| Nobody from a client | Write `admin_audit_log`; touch `schema_migrations` |

**Signup:** a trigger on `auth.users` creates a `profiles` row (role `member`) for every new user. Clients never
insert profiles. A trigger (`guard_profile_role`) stops anyone but an admin from changing a role, including their own.

**Rules when you add tables:** enable RLS in the same migration; give public content a public-read policy and an
admin-write policy; give personal data own-rows-only policies; never put secrets in a public-read table
(`site_settings` is public).

## 5. Theming (database → CSS)

`themes` holds one row per theme; `theme_data` is the design-token set (light and dark CSS variables, fonts, radii,
shadows). `site_settings.active_theme` picks the active one, `theme_mode` the default mode.

```sql
select public.get_active_theme();                 -- the active theme as one JSON object
update site_settings set value = '"ocean"' where key = 'active_theme';   -- admin
```

Seeded themes: `default` (neutral), `ocean`, `forest`. To add one, insert a row; validate it first with
`validateTheme()` from `@core/theme` (it rejects values that could break out of a stylesheet). Colour tokens are HSL
triplets without the wrapper, e.g. `221 83% 53%`.

## 6. i18n (database → messages)

`languages` lists what the site offers (exactly one default); `translations` holds `(locale, namespace, key) → value`.
`get_translations(locale, namespaces)` returns one flat `{"ns.key": "text"}` object: the default language, overlaid by
the base language (`pt`), overlaid by the exact locale (`pt-BR`). A half-translated language still shows every string.

```sql
insert into languages (code, name, native_name) values ('fr', 'French', 'Français');
insert into translations (locale, namespace, key, value) values ('fr', 'common', 'save', 'Enregistrer');
```

Plural forms are separate keys suffixed with the CLDR category: `common.items_one`, `common.items_other`.
Placeholders are `{name}`. Seeded: English (default) and Spanish for `common`, `auth`, `nav`, `theme`, `i18n`, `errors`.

## 7. Writing migrations

* Files are `supabase/migrations/NNNN_name.sql` (digits, underscore, name). They run in numeric order.
* Start with `BEGIN;` and end with `COMMIT;`. One concern per file.
* **Never edit a migration that has been applied** — add the next one.
* Make seeds idempotent (`on conflict do nothing`) so a rebuild is safe.
* `0001_core.sql` is the baseline. Don't hand-edit it; later migrations change the schema from there.

## 8. Known gaps

* The browser URL (`db.<slug>.<domain>`) needs an NPM host before any in-browser sign-in works; server calls work now.
* Storage object policies are not part of the core yet (buckets are public-read; writes go through the service role).
* The Docker group name for the instance carries a timestamp.
