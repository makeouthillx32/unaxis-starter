/**
 * A theme is a set of design tokens. The shape matches `public.themes.theme_data`
 * (and the shadcn token vocabulary), so a theme can be authored in the database,
 * exported, and shared as plain JSON.
 *
 * Colour tokens are HSL triplets WITHOUT the `hsl()` wrapper, e.g. "36 33% 97%",
 * because the UI library composes them with an alpha: `hsl(var(--primary) / 0.5)`.
 */
export type TokenMap = Record<string, string>;

export interface Theme {
  id: string;
  name: string;
  description?: string;
  /** Any CSS colour, used for swatches in a theme picker. */
  previewColor?: string;
  /** Light-mode tokens, keyed by CSS variable name: "--background". */
  light: TokenMap;
  /** Dark-mode tokens. Missing keys fall back to the light value. */
  dark: TokenMap;
  fonts?: { sans?: string; serif?: string; mono?: string };
  radii?: { radius?: string };
  /** camelCase keys -> `--shadow-*` variables (shadowSm -> --shadow-sm). */
  shadows?: Record<string, string>;
  typography?: { trackingNormal?: string };
}

export type ThemeMode = "light" | "dark" | "system";

/** A row of `public.themes` as PostgREST returns it. */
export interface ThemeRow {
  id: string;
  name: string;
  description: string | null;
  preview_color: string | null;
  theme_data: unknown;
  is_system?: boolean;
  is_active?: boolean;
}

/** Tokens every complete theme defines (the shadcn contract the UI library reads). */
export const REQUIRED_TOKENS = [
  "--background", "--foreground", "--card", "--card-foreground", "--popover", "--popover-foreground",
  "--primary", "--primary-foreground", "--secondary", "--secondary-foreground", "--muted",
  "--muted-foreground", "--accent", "--accent-foreground", "--destructive", "--destructive-foreground",
  "--border", "--input", "--ring",
] as const;
