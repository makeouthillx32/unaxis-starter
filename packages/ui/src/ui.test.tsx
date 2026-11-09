import { describe, expect, test } from "bun:test";
import { createRequire } from "module";
import { renderToStaticMarkup } from "react-dom/server";
import { REQUIRED_TOKENS } from "../../theme/src/index.ts";
import {
  Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, LanguageSwitcher, Skeleton,
  Table, TableBody, TableCell, TableRow, ThemeModeToggle, ThemePicker, cn,
} from "./index.ts";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const require = createRequire(import.meta.url);

describe("components render", () => {
  test("button variants and sizes", () => {
    const out = html(<Button variant="destructive" size="sm">Delete</Button>);
    expect(out).toContain("<button");
    expect(out).toContain("Delete");
    expect(out).toContain("bg-destructive");
  });

  test("asChild renders the child element, not a button", () => {
    expect(html(<Button asChild><a href="/x">Go</a></Button>)).toMatch(/^<a href="\/x"/);
  });

  test("card, badge, input, skeleton, table", () => {
    // Components read the theme variables directly, so they need no Tailwind preset.
    expect(html(<Card><CardHeader><CardTitle>T</CardTitle></CardHeader><CardContent>c</CardContent></Card>)).toContain("hsl(var(--card))");
    expect(html(<Badge>New</Badge>)).toContain("New");
    expect(html(<Input placeholder="Email" />)).toContain('placeholder="Email"');
    expect(html(<Skeleton className="h-4" />)).toContain("animate-pulse");
    expect(html(<Table><TableBody><TableRow><TableCell>x</TableCell></TableRow></TableBody></Table>)).toContain("<table");
  });

  test("cn lets later Tailwind classes win", () => {
    expect(cn("px-2 py-1", "px-4")).toBe("py-1 px-4");
  });
});

describe("theme + language controls", () => {
  test("mode toggle marks exactly the current mode", () => {
    const out = html(<ThemeModeToggle value="dark" onChange={() => {}} labels={{ dark: "Oscuro" }} ariaLabel="Tema" />);
    expect(out).toContain('aria-label="Tema"');
    expect(out).toContain("Oscuro");
    expect(out.match(/aria-checked="true"/g)?.length).toBe(1);
    expect(out.match(/role="radio"/g)?.length).toBe(3);
  });

  test("theme picker shows swatches and the selection", () => {
    const out = html(<ThemePicker themes={[{ id: "a", name: "A", previewColor: "red" }, { id: "b", name: "B" }]} value="b" onChange={() => {}} />);
    expect(out).toContain("background:red");
    expect(out).toMatch(/aria-checked="true"[^>]*>(?:(?!<button).)*B/);
  });

  test("language switcher lists native names", () => {
    const out = html(<LanguageSwitcher languages={[{ code: "en", native_name: "English" }, { code: "es", native_name: "Español" }]} value="es" onChange={() => {}} ariaLabel="Idioma" />);
    expect(out).toContain('aria-label="Idioma"');
    expect(out).toContain(">Español<");
    expect(out).toMatch(/<option value="es" selected/);
  });
});

describe("components only read variables the theme engine provides", () => {
  test("every var(--x) in a component is a required token or a shared token", async () => {
    const { readdirSync, readFileSync } = await import("fs");
    const dir = new URL("./components/", import.meta.url);
    const provided = new Set<string>([...REQUIRED_TOKENS, "--radius", "--font-sans", "--font-serif", "--font-mono", "--tracking-normal"]);
    const isShadow = (v: string) => /^--shadow(-(2xs|xs|sm|md|lg|xl|2xl))?$/.test(v);
    const unknown = new Set<string>();
    for (const f of readdirSync(dir)) {
      for (const m of readFileSync(new URL(f, dir), "utf8").matchAll(/var\((--[a-z0-9-]+)\)/g)) {
        if (!provided.has(m[1]!) && !isShadow(m[1]!)) unknown.add(`${f}: ${m[1]}`);
      }
    }
    expect([...unknown]).toEqual([]);
  });
});

describe("tailwind preset <-> theme tokens contract", () => {
  const preset = require("../tailwind-preset.cjs");
  const colors = JSON.stringify(preset.theme.extend.colors);

  test("every token a theme must define is wired to a utility", () => {
    for (const t of REQUIRED_TOKENS) {
      expect(colors).toContain(`hsl(var(${t}) / <alpha-value>)`);
    }
  });

  test("radius, fonts and shadows read the variables the theme engine writes", () => {
    expect(preset.theme.extend.borderRadius.lg).toBe("var(--radius)");
    expect(preset.theme.extend.fontFamily.sans[0]).toBe("var(--font-sans)");
    expect(preset.theme.extend.boxShadow["2xl"]).toBe("var(--shadow-2xl)");
    expect(preset.darkMode).toBe("class");
  });
});
