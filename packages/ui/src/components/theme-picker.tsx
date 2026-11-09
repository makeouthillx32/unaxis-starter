import * as React from "react";
import { cn } from "../lib/utils";

export interface ThemeOption {
  id: string;
  name: string;
  /** Any CSS colour, shown as a swatch. */
  previewColor?: string;
}

export interface ThemePickerProps {
  themes: readonly ThemeOption[];
  value: string;
  onChange: (id: string) => void;
  ariaLabel?: string;
  className?: string;
}

/** A row of theme swatches. Feed it `loadThemes()` from @core/theme. */
export function ThemePicker({ themes, value, onChange, ariaLabel = "Theme", className }: ThemePickerProps) {
  return (
    <div role="radiogroup" aria-label={ariaLabel} className={cn("flex flex-wrap gap-2", className)}>
      {themes.map((t) => (
        <button
          key={t.id}
          type="button"
          role="radio"
          aria-checked={value === t.id}
          onClick={() => onChange(t.id)}
          className={cn(
            "flex items-center gap-2 rounded-md border px-3 py-1.5 text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            value === t.id ? "border-primary bg-accent text-accent-foreground" : "hover:bg-muted",
          )}
        >
          <span aria-hidden className="h-4 w-4 rounded-full border" style={{ background: t.previewColor ?? "currentColor" }} />
          {t.name}
        </button>
      ))}
    </div>
  );
}
