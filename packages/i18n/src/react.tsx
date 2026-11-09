"use client";

import { createContext, createElement, useContext, useMemo, type ReactNode } from "react";
import { createTranslator, type Catalog, type Translator } from "./core.ts";

const I18nContext = createContext<Translator | null>(null);

export interface I18nProviderProps {
  locale: string;
  fallback: string;
  catalog: Catalog;
  onMissing?: (key: string, locale: string) => void;
  children?: ReactNode;
}

export function I18nProvider({ locale, fallback, catalog, onMissing, children }: I18nProviderProps) {
  const value = useMemo(() => createTranslator({ locale, fallback, catalog, onMissing }), [locale, fallback, catalog, onMissing]);
  return createElement(I18nContext.Provider, { value }, children);
}

/** The translator for the nearest provider. Throws outside one, so a missing provider is loud. */
export function useI18n(): Translator {
  const v = useContext(I18nContext);
  if (!v) throw new Error("useI18n must be used inside <I18nProvider>");
  return v;
}

/** Shorthand: `const t = useT(); t("common.save")`. */
export function useT(): Translator["t"] {
  return useI18n().t;
}
