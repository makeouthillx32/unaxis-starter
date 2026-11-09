// ── Types ─────────────────────────────────────────────────────────────────────

/** Flat message map. Keys are "namespace.key", e.g. "auth.sign_in". */
export type Messages = Record<string, string>;

/** locale -> messages */
export type Catalog = Record<string, Messages>;

export type Vars = Record<string, string | number>;

export interface Translator {
  /** The locale actually in use (after negotiation). */
  locale: string;
  dir: "ltr" | "rtl";
  /** Translate. Falls back through the chain; an unknown key returns the key. */
  t(key: string, vars?: Vars): string;
  /** True if the key resolves in any locale of the chain. */
  has(key: string): boolean;
  formatNumber(n: number, opts?: Intl.NumberFormatOptions): string;
  formatDate(d: Date | number | string, opts?: Intl.DateTimeFormatOptions): string;
}

export interface TranslatorOptions {
  locale: string;
  /** Last-resort locale, normally the site's default. */
  fallback: string;
  catalog: Catalog;
  /** Called once per missing key — wire this to logging in development. */
  onMissing?: (key: string, locale: string) => void;
}

// ── Locale negotiation ────────────────────────────────────────────────────────

const lang = (l: string) => l.split("-")[0]!.toLowerCase();

/** Parse an Accept-Language header into locales, best first (by q). */
export function parseAcceptLanguage(header: string | null | undefined): string[] {
  if (!header) return [];
  return header
    .split(",")
    .map((part, i) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => /^\s*q=([0-9.]+)\s*$/.exec(p)?.[1]).find(Boolean);
      return { tag: tag!.trim(), q: q === undefined ? 1 : Number(q), i };
    })
    .filter((x) => x.tag && x.tag !== "*" && Number.isFinite(x.q) && x.q > 0)
    .sort((a, b) => b.q - a.q || a.i - b.i)
    .map((x) => x.tag);
}

/**
 * Pick the best supported locale for what the user asked for.
 * Exact match wins, then same language (en-GB -> en, or en -> en-US), else fallback.
 */
export function negotiateLocale(requested: readonly string[], supported: readonly string[], fallback: string): string {
  const byLower = new Map(supported.map((s) => [s.toLowerCase(), s]));
  for (const r of requested) {
    const exact = byLower.get(r.toLowerCase());
    if (exact) return exact;
    const sameLang = supported.find((s) => lang(s) === lang(r));
    if (sameLang) return sameLang;
  }
  return fallback;
}

export const LOCALE_COOKIE = "core-locale";

/** Cookie first (an explicit choice), then Accept-Language, then the default. */
export function pickLocale(args: { cookie?: string | null; acceptLanguage?: string | null; supported: readonly string[]; fallback: string }): string {
  const requested = [...(args.cookie ? [args.cookie] : []), ...parseAcceptLanguage(args.acceptLanguage)];
  return negotiateLocale(requested, args.supported, args.fallback);
}

const RTL = new Set(["ar", "he", "fa", "ur", "ps", "sd", "ug", "yi", "dv"]);
export const direction = (locale: string): "ltr" | "rtl" => (RTL.has(lang(locale)) ? "rtl" : "ltr");

/** [locale, language, fallback], deduplicated — the lookup order. */
export function localeChain(locale: string, fallback: string): string[] {
  return [...new Set([locale, lang(locale), fallback, lang(fallback)])];
}

// ── Translator ────────────────────────────────────────────────────────────────

const hasOwn = (o: object, k: string) => Object.prototype.hasOwnProperty.call(o, k);

function interpolate(msg: string, vars?: Vars): string {
  if (!vars) return msg;
  return msg.replace(/\{([a-zA-Z0-9_]+)\}/g, (whole, name: string) => (hasOwn(vars, name) ? String(vars[name]) : whole));
}

export function createTranslator(opts: TranslatorOptions): Translator {
  const chain = localeChain(opts.locale, opts.fallback);
  const missing = new Set<string>();

  const lookup = (key: string): string | undefined => {
    for (const l of chain) {
      const m = opts.catalog[l];
      if (m && hasOwn(m, key)) return m[key];
    }
    return undefined;
  };

  const pluralKey = (key: string, count: number): string | undefined => {
    const cat = new Intl.PluralRules(opts.locale).select(count); // zero|one|two|few|many|other
    for (const k of [`${key}_${cat}`, `${key}_other`]) if (lookup(k) !== undefined) return k;
    return undefined;
  };

  return {
    locale: opts.locale,
    dir: direction(opts.locale),
    has: (key) => lookup(key) !== undefined,
    t(key, vars) {
      const count = vars && hasOwn(vars, "count") ? Number(vars.count) : NaN;
      const resolvedKey = Number.isFinite(count) ? (pluralKey(key, count) ?? key) : key;
      const msg = lookup(resolvedKey);
      if (msg === undefined) {
        if (!missing.has(key)) { missing.add(key); opts.onMissing?.(key, opts.locale); }
        return key;
      }
      return interpolate(msg, vars);
    },
    formatNumber: (n, o) => new Intl.NumberFormat(opts.locale, o).format(n),
    formatDate: (d, o) => new Intl.DateTimeFormat(opts.locale, o).format(typeof d === "string" ? new Date(d) : d),
  };
}

// ── Database rows ─────────────────────────────────────────────────────────────

export interface TranslationRow { namespace: string; key: string; value: string }

export function rowsToMessages(rows: readonly TranslationRow[]): Messages {
  const out: Messages = {};
  for (const r of rows) out[`${r.namespace}.${r.key}`] = r.value;
  return out;
}

/** Merge catalogs; later ones win. Used to layer a project's strings over the core's. */
export function mergeCatalogs(...cats: Catalog[]): Catalog {
  const out: Catalog = {};
  for (const c of cats) for (const [l, m] of Object.entries(c)) out[l] = { ...(out[l] ?? {}), ...m };
  return out;
}
