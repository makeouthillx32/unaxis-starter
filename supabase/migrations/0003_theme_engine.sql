-- 0003_theme_engine.sql — database-backed themes
--
-- Themes live in public.themes (created in 0001): one row per theme, the design
-- tokens in `theme_data` (shadcn vocabulary: light/dark CSS variables, fonts,
-- radii, shadows). The @core/theme package turns a row into CSS.
--
-- This migration adds:
--   • public.site_settings   small public key/value store (active theme, default mode, default locale)
--   • public.get_active_theme()   the active theme as one JSON object, in one request
--   • three system themes to start from: default (neutral), ocean, forest
--
-- site_settings is PUBLIC-READ by design — never store secrets in it.

BEGIN;

CREATE TABLE public.site_settings (
  key        text PRIMARY KEY,
  value      jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER site_settings_updated_at BEFORE UPDATE ON public.site_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.site_settings FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY admin_write ON public.site_settings FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.site_settings FROM anon, authenticated;

INSERT INTO public.site_settings (key, value) VALUES
  ('active_theme',   '"default"'),
  ('theme_mode',     '"system"'),   -- light | dark | system
  ('default_locale', '"en"')
ON CONFLICT (key) DO NOTHING;

-- The active theme (falls back to any active system theme), as a single object:
--   POST /rest/v1/rpc/get_active_theme   ->   { id, name, description, preview_color, theme_data, ... }
CREATE FUNCTION public.get_active_theme() RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
  SELECT to_jsonb(t) FROM public.themes t
  WHERE t.is_active IS NOT FALSE
  ORDER BY (t.id = (SELECT value #>> '{}' FROM public.site_settings WHERE key = 'active_theme')) DESC,
           t.is_system DESC NULLS LAST, t.created_at
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_active_theme() TO anon, authenticated;

-- ── Seed: system themes ────────────────────────────────────────────────────
-- Built from one neutral base; the others override the accent colours.
WITH base AS (
  SELECT jsonb_build_object(
    'light', jsonb_build_object(
      '--background','0 0% 100%','--foreground','0 0% 3.9%','--card','0 0% 100%','--card-foreground','0 0% 3.9%',
      '--popover','0 0% 100%','--popover-foreground','0 0% 3.9%','--primary','0 0% 9%','--primary-foreground','0 0% 98%',
      '--secondary','0 0% 96.1%','--secondary-foreground','0 0% 9%','--muted','0 0% 96.1%','--muted-foreground','0 0% 45.1%',
      '--accent','0 0% 96.1%','--accent-foreground','0 0% 9%','--destructive','0 84.2% 60.2%','--destructive-foreground','0 0% 98%',
      '--border','0 0% 89.8%','--input','0 0% 89.8%','--ring','0 0% 3.9%',
      '--chart-1','12 76% 61%','--chart-2','173 58% 39%','--chart-3','197 37% 24%','--chart-4','43 74% 66%','--chart-5','27 87% 67%'
    ),
    'dark', jsonb_build_object(
      '--background','0 0% 3.9%','--foreground','0 0% 98%','--card','0 0% 3.9%','--card-foreground','0 0% 98%',
      '--popover','0 0% 3.9%','--popover-foreground','0 0% 98%','--primary','0 0% 98%','--primary-foreground','0 0% 9%',
      '--secondary','0 0% 14.9%','--secondary-foreground','0 0% 98%','--muted','0 0% 14.9%','--muted-foreground','0 0% 63.9%',
      '--accent','0 0% 14.9%','--accent-foreground','0 0% 98%','--destructive','0 62.8% 30.6%','--destructive-foreground','0 0% 98%',
      '--border','0 0% 14.9%','--input','0 0% 14.9%','--ring','0 0% 83.1%',
      '--chart-1','220 70% 50%','--chart-2','160 60% 45%','--chart-3','30 80% 55%','--chart-4','280 65% 60%','--chart-5','340 75% 55%'
    ),
    'fonts', jsonb_build_object('sans','Inter, ui-sans-serif, system-ui, sans-serif','serif','ui-serif, Georgia, serif','mono','ui-monospace, SFMono-Regular, Menlo, monospace'),
    'radii', jsonb_build_object('radius','0.5rem'),
    'shadows', jsonb_build_object(
      'shadow2xs','0 1px 2px 0 hsl(0 0% 0% / 0.05)','shadowXs','0 1px 2px 0 hsl(0 0% 0% / 0.05)',
      'shadowSm','0 1px 3px 0 hsl(0 0% 0% / 0.10), 0 1px 2px -1px hsl(0 0% 0% / 0.10)',
      'shadow','0 1px 3px 0 hsl(0 0% 0% / 0.10), 0 1px 2px -1px hsl(0 0% 0% / 0.10)',
      'shadowMd','0 4px 6px -1px hsl(0 0% 0% / 0.10), 0 2px 4px -2px hsl(0 0% 0% / 0.10)',
      'shadowLg','0 10px 15px -3px hsl(0 0% 0% / 0.10), 0 4px 6px -4px hsl(0 0% 0% / 0.10)',
      'shadowXl','0 20px 25px -5px hsl(0 0% 0% / 0.10), 0 8px 10px -6px hsl(0 0% 0% / 0.10)',
      'shadow2xl','0 25px 50px -12px hsl(0 0% 0% / 0.25)'
    ),
    'typography', jsonb_build_object('trackingNormal','0em')
  ) AS j
)
INSERT INTO public.themes (id, name, description, preview_color, theme_data, is_system, is_active)
SELECT 'default', 'Default', 'Clean neutral greys.', 'hsl(0 0% 9%)', j, true, true FROM base
UNION ALL
SELECT 'ocean', 'Ocean', 'Cool blues.', 'hsl(221.2 83.2% 53.3%)',
  jsonb_set(jsonb_set(j, '{light}', (j->'light') || '{"--primary":"221.2 83.2% 53.3%","--primary-foreground":"210 40% 98%","--ring":"221.2 83.2% 53.3%","--accent":"214 32% 94%","--accent-foreground":"222 47% 11%"}'::jsonb),
                      '{dark}',  (j->'dark')  || '{"--primary":"217.2 91.2% 59.8%","--primary-foreground":"222.2 47.4% 11.2%","--ring":"224.3 76.3% 48%","--accent":"217.2 32.6% 17.5%","--accent-foreground":"210 40% 98%"}'::jsonb),
  true, true FROM base
UNION ALL
SELECT 'forest', 'Forest', 'Natural greens.', 'hsl(142.1 76.2% 36.3%)',
  jsonb_set(jsonb_set(j, '{light}', (j->'light') || '{"--primary":"142.1 76.2% 36.3%","--primary-foreground":"355.7 100% 97.3%","--ring":"142.1 76.2% 36.3%","--accent":"138 76% 95%","--accent-foreground":"142 72% 20%"}'::jsonb),
                      '{dark}',  (j->'dark')  || '{"--primary":"142.1 70.6% 45.3%","--primary-foreground":"144.9 80.4% 10%","--ring":"142.4 71.8% 29.2%","--accent":"143 30% 15%","--accent-foreground":"138 76% 90%"}'::jsonb),
  true, true FROM base
ON CONFLICT (id) DO NOTHING;

COMMIT;
