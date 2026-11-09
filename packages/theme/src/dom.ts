import { resolveMode, themeToCss } from "./css.ts";
import type { Theme, ThemeMode } from "./types.ts";

export const THEME_STYLE_ID = "core-theme";

/** The slice of `document` this needs, so it can be tested without a DOM. */
export interface DocLike {
  getElementById(id: string): { textContent: string | null } | null;
  createElement(tag: "style"): { id: string; textContent: string | null };
  head: { appendChild(n: unknown): unknown };
  documentElement: { classList: { toggle(cls: string, force?: boolean): unknown }; style?: { colorScheme?: string } };
}

/**
 * Inject (or update) the theme's CSS and set the light/dark class.
 * Safe to call repeatedly; there is only ever one <style id="core-theme">.
 */
export function applyTheme(theme: Theme, mode: ThemeMode, opts: { systemPrefersDark?: boolean; doc?: DocLike } = {}): "light" | "dark" {
  const doc = opts.doc ?? (globalThis as { document?: DocLike }).document;
  const resolved = resolveMode(mode, opts.systemPrefersDark ?? false);
  if (!doc) return resolved;

  let el = doc.getElementById(THEME_STYLE_ID);
  if (!el) {
    const created = doc.createElement("style");
    created.id = THEME_STYLE_ID;
    doc.head.appendChild(created);
    el = created;
  }
  el.textContent = themeToCss(theme);
  doc.documentElement.classList.toggle("dark", resolved === "dark");
  if (doc.documentElement.style) doc.documentElement.style.colorScheme = resolved;
  return resolved;
}

/**
 * Inline script for <head>: sets the dark class before first paint so a dark
 * user never sees a light flash. `storageKey` holds "light" | "dark" | "system".
 */
export function noFlashScript(storageKey = "core-theme-mode"): string {
  return `(function(){try{var m=localStorage.getItem(${JSON.stringify(storageKey)})||"system";var d=m==="dark"||(m==="system"&&matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.classList.toggle("dark",d)}catch(e){}})();`;
}
