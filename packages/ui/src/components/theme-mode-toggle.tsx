import * as React from "react";
import { cn } from "../lib/utils";

export type ThemeModeValue = "light" | "dark" | "system";

export interface ThemeModeToggleProps {
  value: ThemeModeValue;
  onChange: (mode: ThemeModeValue) => void;
  /** Button labels — pass translated strings (e.g. t("theme.light")). */
  labels?: Partial<Record<ThemeModeValue, string>>;
  /** Accessible name for the group (e.g. t("theme.label")). */
  ariaLabel?: string;
  className?: string;
}

const MODES: ThemeModeValue[] = ["light", "dark", "system"];
const DEFAULT_LABELS: Record<ThemeModeValue, string> = { light: "Light", dark: "Dark", system: "System" };

/**
 * Light / dark / system, as a segmented control. Controlled and framework-free:
 * wire `value`/`onChange` to your own state and to `applyTheme` from @core/theme.
 */
export function ThemeModeToggle({ value, onChange, labels, ariaLabel = "Theme", className }: ThemeModeToggleProps) {
  const text = { ...DEFAULT_LABELS, ...labels };
  return (
    <div role="radiogroup" aria-label={ariaLabel} className={cn("inline-flex rounded-md border bg-muted p-0.5", className)}>
      {MODES.map((m) => (
        <button
          key={m}
          type="button"
          role="radio"
          aria-checked={value === m}
          onClick={() => onChange(m)}
          className={cn(
            "rounded-sm px-3 py-1 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            value === m ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {text[m]}
        </button>
      ))}
    </div>
  );
}
