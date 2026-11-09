import { describe, expect, test } from "bun:test";
import {
  createTranslator, direction, loadLanguages, loadMessages, localeChain, mergeCatalogs,
  negotiateLocale, parseAcceptLanguage, pickLocale, rowsToMessages, type Catalog,
} from "./index.ts";

const catalog: Catalog = {
  en: {
    "common.save": "Save",
    "common.hello": "Hello, {name}!",
    "items.count_one": "{count} item",
    "items.count_other": "{count} items",
    "only.en": "English only",
  },
  es: {
    "common.save": "Guardar",
    "common.hello": "¡Hola, {name}!",
    "items.count_one": "{count} elemento",
    "items.count_other": "{count} elementos",
  },
  "pt-BR": { "common.save": "Salvar" },
};

describe("Accept-Language + negotiation", () => {
  test("orders by q, drops wildcards and q=0", () => {
    expect(parseAcceptLanguage("fr;q=0.5, en-US, es;q=0.9, *;q=0.1, de;q=0")).toEqual(["en-US", "es", "fr"]);
    expect(parseAcceptLanguage(null)).toEqual([]);
  });

  test("exact, then same language either way, else fallback", () => {
    const supported = ["en", "es", "pt-BR"];
    expect(negotiateLocale(["es"], supported, "en")).toBe("es");
    expect(negotiateLocale(["en-GB"], supported, "en")).toBe("en");
    expect(negotiateLocale(["pt"], supported, "en")).toBe("pt-BR");
    expect(negotiateLocale(["PT-br"], supported, "en")).toBe("pt-BR");
    expect(negotiateLocale(["ja", "es-MX"], supported, "en")).toBe("es");
    expect(negotiateLocale(["ja"], supported, "en")).toBe("en");
  });

  test("an explicit cookie beats the browser header", () => {
    expect(pickLocale({ cookie: "es", acceptLanguage: "en-US", supported: ["en", "es"], fallback: "en" })).toBe("es");
    expect(pickLocale({ acceptLanguage: "es-MX,en;q=0.5", supported: ["en", "es"], fallback: "en" })).toBe("es");
    expect(pickLocale({ cookie: "xx", acceptLanguage: "es", supported: ["en", "es"], fallback: "en" })).toBe("es");
  });

  test("direction and chain", () => {
    expect(direction("ar-EG")).toBe("rtl");
    expect(direction("es")).toBe("ltr");
    expect(localeChain("pt-BR", "en")).toEqual(["pt-BR", "pt", "en"]);
    expect(localeChain("en", "en")).toEqual(["en"]);
  });
});

describe("translator", () => {
  test("translates and interpolates", () => {
    const t = createTranslator({ locale: "es", fallback: "en", catalog });
    expect(t.t("common.save")).toBe("Guardar");
    expect(t.t("common.hello", { name: "Ana" })).toBe("¡Hola, Ana!");
  });

  test("falls back locale -> language -> default, per key", () => {
    const t = createTranslator({ locale: "pt-BR", fallback: "en", catalog });
    expect(t.t("common.save")).toBe("Salvar");
    expect(t.t("only.en")).toBe("English only");
  });

  test("missing key returns the key and reports once", () => {
    const seen: string[] = [];
    const t = createTranslator({ locale: "en", fallback: "en", catalog, onMissing: (k) => seen.push(k) });
    expect(t.t("nope.nothing")).toBe("nope.nothing");
    t.t("nope.nothing");
    expect(seen).toEqual(["nope.nothing"]);
    expect(t.has("common.save")).toBe(true);
    expect(t.has("nope.nothing")).toBe(false);
  });

  test("unknown placeholders are left visible, not blanked", () => {
    const t = createTranslator({ locale: "en", fallback: "en", catalog });
    expect(t.t("common.hello", {})).toBe("Hello, {name}!");
  });

  test("placeholder values cannot reach Object.prototype", () => {
    const t = createTranslator({ locale: "en", fallback: "en", catalog: { en: { a: "{toString}{constructor}" } } });
    expect(t.t("a", {})).toBe("{toString}{constructor}");
  });

  test("plural forms by Intl.PluralRules", () => {
    const en = createTranslator({ locale: "en", fallback: "en", catalog });
    expect(en.t("items.count", { count: 1 })).toBe("1 item");
    expect(en.t("items.count", { count: 3 })).toBe("3 items");
    const es = createTranslator({ locale: "es", fallback: "en", catalog });
    expect(es.t("items.count", { count: 1 })).toBe("1 elemento");
    expect(es.t("items.count", { count: 0 })).toBe("0 elementos");
  });

  test("formatting follows the locale", () => {
    const es = createTranslator({ locale: "es", fallback: "en", catalog });
    expect(es.formatNumber(1234.5)).toBe(new Intl.NumberFormat("es").format(1234.5));
    expect(es.dir).toBe("ltr");
  });
});

describe("catalog helpers", () => {
  test("rowsToMessages", () => {
    expect(rowsToMessages([{ namespace: "auth", key: "sign_in", value: "Sign in" }])).toEqual({ "auth.sign_in": "Sign in" });
  });

  test("mergeCatalogs lets a project override core strings", () => {
    const m = mergeCatalogs({ en: { a: "core", b: "core" } }, { en: { a: "project" }, es: { a: "x" } });
    expect(m).toEqual({ en: { a: "project", b: "core" }, es: { a: "x" } });
  });
});

describe("database loading", () => {
  test("loadMessages posts the locale to the RPC with the anon key", async () => {
    let seen: { url: string; body: string; key: string } | null = null;
    const f = (async (url: string, init: RequestInit) => {
      seen = { url: String(url), body: String(init.body), key: (init.headers as Record<string, string>).apikey! };
      return new Response(JSON.stringify({ "common.save": "Guardar" }), { status: 200 });
    }) as unknown as typeof fetch;
    const m = await loadMessages({ url: "http://h:8563/", anonKey: "ANON", fetch: f }, "es", ["common"]);
    expect(m["common.save"]).toBe("Guardar");
    expect(seen!.url).toBe("http://h:8563/rest/v1/rpc/get_translations");
    expect(JSON.parse(seen!.body)).toEqual({ p_locale: "es", p_namespaces: ["common"] });
    expect(seen!.key).toBe("ANON");
  });

  test("HTTP errors surface", async () => {
    const f = (async () => new Response("{}", { status: 401 })) as unknown as typeof fetch;
    await expect(loadLanguages({ url: "http://h", anonKey: "A", fetch: f })).rejects.toThrow("401");
  });
});
