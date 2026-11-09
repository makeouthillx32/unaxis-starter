import { themeFromRow } from "./css.ts";
import type { Theme, ThemeRow } from "./types.ts";

export interface SupabaseLike {
  /** Base URL of the project's API (Kong), e.g. http://host:8563 */
  url: string;
  /** The anon key — themes are public-read by design. */
  anonKey: string;
  fetch?: typeof fetch;
}

async function rest<T>(c: SupabaseLike, path: string, init?: RequestInit): Promise<T> {
  const f = c.fetch ?? fetch;
  const res = await f(`${c.url.replace(/\/$/, "")}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: c.anonKey, Authorization: `Bearer ${c.anonKey}`, "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!res.ok) throw new Error(`theme: ${path} -> HTTP ${res.status}`);
  return (await res.json()) as T;
}

/** The theme chosen in `site_settings.active_theme` (one round trip, via RPC). */
export async function loadActiveTheme(c: SupabaseLike): Promise<Theme | null> {
  const row = await rest<ThemeRow | null>(c, "rpc/get_active_theme", { method: "POST", body: "{}" });
  return row ? themeFromRow(row) : null;
}

/** Every active theme, for a picker. Unusable rows are skipped. */
export async function loadThemes(c: SupabaseLike): Promise<Theme[]> {
  const rows = await rest<ThemeRow[]>(c, "themes?select=id,name,description,preview_color,theme_data,is_system,is_active&is_active=eq.true&order=name.asc");
  return rows.map(themeFromRow).filter((t): t is Theme => t !== null);
}
