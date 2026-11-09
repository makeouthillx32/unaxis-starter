import { REQUIRED_TOKENS, type Theme, type ThemeMode, type ThemeRow, type TokenMap } from "./types.ts";

// ── Safety ────────────────────────────────────────────────────────────────────
// Theme values end up inside a <style> element, and themes are editable by
// admins (and shareable as JSON), so a value must never be able to close the
// rule, open a new one, pull a remote resource or break out of the element.

const SAFE_NAME = /^--[a-z0-9][a-z0-9-]*$/i;
const UNSAFE_VALUE = /[;{}<>\\]|\/\*|\*\/|url\s*\(|@import|expression\s*\(|javascript:/i;

export function isSafeTokenName(name: string): boolean {
  return SAFE_NAME.test(name);
}

export function isSafeCssValue(value: string): boolean {
  return value.length > 0 && value.length <= 400 && !UNSAFE_VALUE.test(value);
}

// ── Validation ────────────────────────────────────────────────────────────────

export interface ThemeIssue {
  path: string;
  message: string;
}

/** Collect problems without throwing, so an editor can show them all. */
export function validateTheme(theme: Theme): ThemeIssue[] {
  const issues: ThemeIssue[] = [];
  if (!theme.id) issues.push({ path: "id", message: "missing id" });
  if (!theme.name) issues.push({ path: "name", message: "missing name" });

  for (const mode of ["light", "dark"] as const) {
    const tokens = theme[mode] ?? {};
    for (const [k, v] of Object.entries(tokens)) {
      if (!isSafeTokenName(k)) issues.push({ path: `${mode}.${k}`, message: "invalid token name" });
      else if (!isSafeCssValue(v)) issues.push({ path: `${mode}.${k}`, message: "unsafe or empty value" });
    }
  }
  for (const k of REQUIRED_TOKENS) {
    if (!(k in (theme.light ?? {}))) issues.push({ path: `light.${k}`, message: "required token missing" });
  }
  for (const [group, map] of [["fonts", theme.fonts], ["radii", theme.radii], ["shadows", theme.shadows], ["typography", theme.typography]] as const) {
    for (const [k, v] of Object.entries(map ?? {})) {
      if (typeof v === "string" && !isSafeCssValue(v)) issues.push({ path: `${group}.${k}`, message: "unsafe or empty value" });
    }
  }
  return issues;
}

// ── Database row → Theme ─────────────────────────────────────────────────────

function isTokenMap(v: unknown): v is TokenMap {
  return !!v && typeof v === "object" && Object.values(v as object).every((x) => typeof x === "string");
}

/** Build a Theme from a `public.themes` row. Returns null when the data isn't usable. */
export function themeFromRow(row: ThemeRow): Theme | null {
  const d = row.theme_data as Partial<Theme> | null;
  if (!d || typeof d !== "object" || !isTokenMap(d.light)) return null;
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? d.description,
    previewColor: row.preview_color ?? d.previewColor,
    light: d.light,
    dark: isTokenMap(d.dark) ? d.dark : {},
    fonts: d.fonts,
    radii: d.radii,
    shadows: d.shadows,
    typography: d.typography,
  };
}

// ── Theme → CSS ──────────────────────────────────────────────────────────────

// shadowSm -> shadow-sm, shadow2xl -> shadow-2xl
const kebab = (s: string) => s.replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/([a-z])(\d)/g, "$1-$2").toLowerCase();

function block(selector: string, vars: [string, string][]): string {
  if (vars.length === 0) return "";
  return `${selector}{${vars.map(([k, v]) => `${k}:${v}`).join(";")}}`;
}

function sharedVars(theme: Theme): [string, string][] {
  const out: [string, string][] = [];
  const f = theme.fonts ?? {};
  if (f.sans) out.push(["--font-sans", f.sans]);
  if (f.serif) out.push(["--font-serif", f.serif]);
  if (f.mono) out.push(["--font-mono", f.mono]);
  if (theme.radii?.radius) out.push(["--radius", theme.radii.radius]);
  if (theme.typography?.trackingNormal) out.push(["--tracking-normal", theme.typography.trackingNormal]);
  for (const [k, v] of Object.entries(theme.shadows ?? {})) out.push([`--${kebab(k)}`, v]);
  return out;
}

function safeEntries(tokens: TokenMap): [string, string][] {
  return Object.entries(tokens).filter(([k, v]) => isSafeTokenName(k) && isSafeCssValue(v));
}

export interface CssOptions {
  /** Selector for light mode + shared tokens. Default ":root". */
  rootSelector?: string;
  /** Selector for dark mode. Default ".dark". */
  darkSelector?: string;
}

/**
 * Render a theme as CSS. Unsafe tokens are DROPPED (never emitted), so the
 * output is always safe to put in a <style> element.
 */
export function themeToCss(theme: Theme, opts: CssOptions = {}): string {
  const root = opts.rootSelector ?? ":root";
  const dark = opts.darkSelector ?? ".dark";
  const shared = sharedVars(theme).filter(([k, v]) => isSafeTokenName(k) && isSafeCssValue(v));
  return [
    block(root, [...shared, ...safeEntries(theme.light)]),
    block(dark, safeEntries(theme.dark)),
  ].filter(Boolean).join("\n");
}

/** The mode to render, resolving "system" against the user's OS preference. */
export function resolveMode(pref: ThemeMode, systemPrefersDark: boolean): "light" | "dark" {
  return pref === "system" ? (systemPrefersDark ? "dark" : "light") : pref;
}
