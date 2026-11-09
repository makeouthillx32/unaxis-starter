import * as React from "react";
import { cn } from "../lib/utils";

export interface LanguageOption {
  code: string;
  /** Shown in the picker, in the language itself ("Español"). */
  native_name: string;
}

export interface LanguageSwitcherProps {
  languages: readonly LanguageOption[];
  value: string;
  onChange: (code: string) => void;
  /** Accessible name (e.g. t("i18n.language")). */
  ariaLabel?: string;
  className?: string;
}

/**
 * A native <select> (keyboard, screen-reader and mobile friendly) styled with the
 * theme tokens. Feed it `loadLanguages()` from @core/i18n; on change, store the
 * choice in the LOCALE_COOKIE and re-render with the new messages.
 */
export function LanguageSwitcher({ languages, value, onChange, ariaLabel = "Language", className }: LanguageSwitcherProps) {
  return (
    <select
      aria-label={ariaLabel}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className={cn(
        "h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        className,
      )}
    >
      {languages.map((l) => (
        <option key={l.code} value={l.code}>{l.native_name}</option>
      ))}
    </select>
  );
}
