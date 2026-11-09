# UNAXIS starter (blank core)

A boilerplate for trying the [UNAXIS](https://unenter.live) platform: a fresh Supabase database (schema + seed),
a UI library, a database-backed theme engine and a database-backed i18n engine. Nothing project-specific, so you
can turn it into anything.

**Quick start with UNAXIS:** clone this repo, point UNAXIS at it as a project, then
`unaxis <env> project-stack create <slug>` — UNAXIS picks a host, creates a fresh database and applies
`supabase/migrations`. Add more migrations later with `unaxis <env> project-stack migrate <slug>`.

| Package | What it is |
|---|---|
| [`@core/ui`](packages/ui) | shadcn-style React components (22 components) + a theme mode toggle, theme picker and language switcher. Driven entirely by CSS variables, so any theme works |
| [`@core/theme`](packages/theme) | Design tokens in the database → safe CSS. Load, validate, apply; no-flash dark mode |
| [`@core/i18n`](packages/i18n) | Locale negotiation, fallback chain, plurals, `{placeholders}`, DB loading. React bindings in `@core/i18n/react` |
| [`supabase/migrations`](supabase/migrations) | The core schema, security policies, and seed (themes, languages, strings) |

How the database works and how to connect to it: **[docs/DATABASE.md](docs/DATABASE.md)**.

```bash
bun install
bun test packages          # 40 tests
bun run typecheck
```

## Using it

**1. Theme — render the active theme on the server, so there is no flash.**

```tsx
// app/layout.tsx  (server component)
import { loadActiveTheme, themeToCss, noFlashScript } from "@core/theme";
import { I18nProvider } from "@core/i18n/react";
import { LOCALE_COOKIE, loadLanguages, loadMessages, pickLocale } from "@core/i18n";
import { cookies, headers } from "next/headers";

const conn = { url: process.env.SUPABASE_URL!, anonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! };

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const [theme, languages] = await Promise.all([loadActiveTheme(conn), loadLanguages(conn)]);
  const fallback = languages.find((l) => l.is_default)?.code ?? "en";
  const locale = pickLocale({
    cookie: (await cookies()).get(LOCALE_COOKIE)?.value,
    acceptLanguage: (await headers()).get("accept-language"),
    supported: languages.map((l) => l.code),
    fallback,
  });
  const catalog = { [fallback]: await loadMessages(conn, fallback), [locale]: await loadMessages(conn, locale) };

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        {theme && <style dangerouslySetInnerHTML={{ __html: themeToCss(theme) }} />}
        <script dangerouslySetInnerHTML={{ __html: noFlashScript() }} />
      </head>
      <body>
        <I18nProvider locale={locale} fallback={fallback} catalog={catalog}>{children}</I18nProvider>
      </body>
    </html>
  );
}
```

`themeToCss` drops any token that could break out of a `<style>` element, so a theme edited in the database can't inject markup.

**2. Components — tokens are variables, so no extra setup.**

```tsx
import { Button, Card, CardHeader, CardTitle, CardContent, ThemeModeToggle, LanguageSwitcher } from "@core/ui";
import { useT } from "@core/i18n/react";

const t = useT();
<Card><CardHeader><CardTitle>{t("nav.dashboard")}</CardTitle></CardHeader>
  <CardContent><Button>{t("common.save")}</Button></CardContent></Card>
```

Optional: `presets: [require("@core/ui/tailwind-preset")]` gives your own markup `bg-primary`, `rounded-lg`, `shadow-md`, etc.
mapped to the same variables.

**3. Translate.** Keys are `namespace.key`. Plurals: `t("common.items", { count: 3 })` picks `common.items_one` /
`common.items_other` by the locale's rules. A missing key renders as the key itself (and can be reported through `onMissing`).

## Adding to it

* A theme: insert a `themes` row (validate with `validateTheme`). A language: insert into `languages` + `translations`.
* A component: add it under `packages/ui/src/components`, read only the theme variables (a test enforces this), export it.
* Schema: a new `supabase/migrations/NNNN_name.sql` — with RLS. Apply with `unaxis <env> project-stack migrate <slug>`.

## Not included yet

The heavier shadcn components (chart, calendar, carousel, sidebar, form, resizable) and a theme editor UI.

## License

MIT — see [LICENSE](LICENSE).
