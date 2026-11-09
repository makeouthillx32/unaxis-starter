import { describe, expect, test } from "bun:test";
import {
  REQUIRED_TOKENS, THEME_STYLE_ID, applyTheme, isSafeCssValue, loadActiveTheme, loadThemes,
  noFlashScript, resolveMode, themeFromRow, themeToCss, validateTheme, type Theme,
} from "./index.ts";

const tokens = (v: string) => Object.fromEntries(REQUIRED_TOKENS.map((k) => [k, v]));

const theme: Theme = {
  id: "t", name: "T",
  light: { ...tokens("0 0% 100%"), "--primary": "24 60% 45%" },
  dark: { "--background": "0 0% 5%" },
  fonts: { sans: "Inter, sans-serif" },
  radii: { radius: "0.5rem" },
  shadows: { shadowSm: "0 1px 2px #0002", shadow2xl: "0 8px 20px #0004" },
  typography: { trackingNormal: "-0.01em" },
};

describe("themeToCss", () => {
  const css = themeToCss(theme);

  test("light tokens + shared tokens go in :root, dark in .dark", () => {
    expect(css).toContain(":root{");
    expect(css).toContain("--primary:24 60% 45%");
    expect(css).toContain("--font-sans:Inter, sans-serif");
    expect(css).toContain("--radius:0.5rem");
    expect(css).toContain("--tracking-normal:-0.01em");
    expect(css).toContain(".dark{--background:0 0% 5%}");
  });

  test("camelCase shadow keys become kebab-case variables", () => {
    expect(css).toContain("--shadow-sm:0 1px 2px #0002");
    expect(css).toContain("--shadow-2xl:0 8px 20px #0004");
  });

  test("custom selectors", () => {
    expect(themeToCss(theme, { rootSelector: "[data-t]", darkSelector: "[data-t].dark" })).toContain("[data-t].dark{");
  });
});

describe("safety: a theme can never break out of its <style>", () => {
  const evil: Theme = {
    ...theme,
    light: {
      ...theme.light,
      "--bad;color": "red",                       // bad name
      "--x": "1;} body{display:none} .a{",        // closes the rule
      "--y": "url(https://evil.example/x.png)",    // remote fetch
      "--z": "</style><script>alert(1)</script>", // element break-out
      "--w": "1; @import 'x'",
    },
  };
  const css = themeToCss(evil);

  test("unsafe names and values are dropped, safe ones survive", () => {
    for (const bad of ["evil.example", "</style>", "@import", "display:none", "--bad", "alert(1)"]) {
      expect(css).not.toContain(bad);
    }
    expect(css).toContain("--primary:24 60% 45%");
  });

  test("validateTheme reports them", () => {
    const paths = validateTheme(evil).map((i) => i.path);
    expect(paths).toContain("light.--x");
    expect(paths).toContain("light.--y");
    expect(paths).toContain("light.--z");
  });

  test("isSafeCssValue", () => {
    expect(isSafeCssValue("24 60% 45%")).toBe(true);
    expect(isSafeCssValue("hsl(24 60% 45% / 0.1)")).toBe(true);
    expect(isSafeCssValue("")).toBe(false);
    expect(isSafeCssValue("a;b")).toBe(false);
    expect(isSafeCssValue("x".repeat(401))).toBe(false);
  });
});

describe("validateTheme", () => {
  test("a complete theme is valid", () => expect(validateTheme(theme)).toEqual([]));

  test("missing required tokens are reported", () => {
    const issues = validateTheme({ ...theme, light: { "--background": "0 0% 100%" } });
    expect(issues.some((i) => i.path === "light.--primary")).toBe(true);
  });
});

describe("themeFromRow", () => {
  test("reads the database shape", () => {
    const t = themeFromRow({ id: "default", name: "Default", description: "d", preview_color: "red", theme_data: { light: tokens("1 1% 1%"), dark: {}, fonts: { sans: "X" } } });
    expect(t?.id).toBe("default");
    expect(t?.previewColor).toBe("red");
    expect(t?.fonts?.sans).toBe("X");
  });

  test("unusable data yields null instead of throwing", () => {
    expect(themeFromRow({ id: "x", name: "x", description: null, preview_color: null, theme_data: null })).toBeNull();
    expect(themeFromRow({ id: "x", name: "x", description: null, preview_color: null, theme_data: { light: { a: 1 } } })).toBeNull();
  });
});

describe("mode + DOM", () => {
  test("resolveMode", () => {
    expect(resolveMode("system", true)).toBe("dark");
    expect(resolveMode("system", false)).toBe("light");
    expect(resolveMode("dark", false)).toBe("dark");
  });

  test("applyTheme keeps a single style element and toggles the dark class", () => {
    const els: Record<string, { id: string; textContent: string | null }> = {};
    let darkOn: boolean | undefined;
    const doc = {
      getElementById: (id: string) => els[id] ?? null,
      createElement: () => ({ id: "", textContent: null as string | null }),
      head: { appendChild: (n: { id: string; textContent: string | null }) => { els[n.id] = n; } },
      documentElement: { classList: { toggle: (_c: string, f?: boolean) => { darkOn = f; } }, style: {} as { colorScheme?: string } },
    };
    expect(applyTheme(theme, "dark", { doc })).toBe("dark");
    expect(darkOn).toBe(true);
    applyTheme(theme, "light", { doc });
    expect(Object.keys(els)).toEqual([THEME_STYLE_ID]);
    expect(els[THEME_STYLE_ID]?.textContent).toContain("--primary");
    expect(darkOn).toBe(false);
  });

  test("no-flash script is valid JS", () => {
    expect(() => new Function(noFlashScript())).not.toThrow();
  });
});

describe("database loading", () => {
  const row = { id: "default", name: "Default", description: null, preview_color: null, theme_data: { light: tokens("0 0% 0%"), dark: {} } };
  const fakeFetch = (body: unknown, status = 200) =>
    (async (url: string, init?: RequestInit) => {
      calls.push({ url: String(url), init });
      return new Response(JSON.stringify(body), { status });
    }) as unknown as typeof fetch;
  const calls: { url: string; init?: RequestInit }[] = [];

  test("loadActiveTheme calls the RPC with the anon key", async () => {
    calls.length = 0;
    const t = await loadActiveTheme({ url: "http://h:8563/", anonKey: "ANON", fetch: fakeFetch(row) });
    expect(t?.id).toBe("default");
    expect(calls[0]?.url).toBe("http://h:8563/rest/v1/rpc/get_active_theme");
    expect((calls[0]?.init?.headers as Record<string, string>).apikey).toBe("ANON");
  });

  test("loadThemes skips unusable rows and surfaces HTTP errors", async () => {
    const list = await loadThemes({ url: "http://h", anonKey: "A", fetch: fakeFetch([row, { ...row, id: "bad", theme_data: null }]) });
    expect(list.map((t) => t.id)).toEqual(["default"]);
    await expect(loadThemes({ url: "http://h", anonKey: "A", fetch: fakeFetch({}, 401) })).rejects.toThrow("401");
  });
});
