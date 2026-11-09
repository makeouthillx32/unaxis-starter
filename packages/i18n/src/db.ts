import type { Messages } from "./core.ts";

export interface SupabaseLike {
  url: string;
  /** The anon key — languages and translations are public-read by design. */
  anonKey: string;
  fetch?: typeof fetch;
}

export interface Language {
  code: string;
  name: string;
  native_name: string;
  direction: "ltr" | "rtl";
  is_default: boolean;
}

async function call<T>(c: SupabaseLike, path: string, init?: RequestInit): Promise<T> {
  const f = c.fetch ?? fetch;
  const res = await f(`${c.url.replace(/\/$/, "")}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: c.anonKey, Authorization: `Bearer ${c.anonKey}`, "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!res.ok) throw new Error(`i18n: ${path} -> HTTP ${res.status}`);
  return (await res.json()) as T;
}

/** Enabled languages, default first. */
export async function loadLanguages(c: SupabaseLike): Promise<Language[]> {
  return call<Language[]>(c, "languages?select=code,name,native_name,direction,is_default&is_enabled=eq.true&order=is_default.desc,code.asc");
}

/**
 * One locale's messages as a flat "ns.key" map. The server merges the locale
 * over the default locale, so a half-translated language still renders fully.
 * Pass `namespaces` to load only what a page needs.
 */
export async function loadMessages(c: SupabaseLike, locale: string, namespaces?: string[]): Promise<Messages> {
  return call<Messages>(c, "rpc/get_translations", {
    method: "POST",
    body: JSON.stringify({ p_locale: locale, p_namespaces: namespaces ?? null }),
  });
}
