-- 0004_i18n.sql — database-backed translations
--
-- public.languages     the languages the site offers (code, names, direction, enabled)
-- public.translations  one row per (locale, namespace, key) -> value
-- public.get_translations(locale, namespaces)  one request -> a flat {"ns.key": "text"} object
--
-- The @core/i18n package loads that object and does lookup, fallback, plurals and
-- interpolation. Keys are "namespace.key"; plural forms are suffixed by the CLDR
-- category (key_one, key_other, ...), e.g. common.items_one / common.items_other.
--
-- Both tables are PUBLIC-READ (they feed the UI) and admin-write.

BEGIN;

CREATE TABLE public.languages (
  code        text PRIMARY KEY,                      -- BCP-47: en, es, pt-BR
  name        text NOT NULL,                         -- English name
  native_name text NOT NULL,                         -- shown in the language picker
  direction   text NOT NULL DEFAULT 'ltr' CHECK (direction IN ('ltr', 'rtl')),
  is_default  boolean NOT NULL DEFAULT false,
  is_enabled  boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
-- Exactly one default language.
CREATE UNIQUE INDEX languages_one_default ON public.languages (is_default) WHERE is_default;

CREATE TABLE public.translations (
  locale     text NOT NULL REFERENCES public.languages (code) ON UPDATE CASCADE ON DELETE CASCADE,
  namespace  text NOT NULL,
  key        text NOT NULL,
  value      text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (locale, namespace, key)
);
CREATE INDEX translations_ns ON public.translations (namespace, key);

CREATE TRIGGER translations_updated_at BEFORE UPDATE ON public.translations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.languages ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.languages FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY admin_write ON public.languages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

ALTER TABLE public.translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.translations FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY admin_write ON public.translations FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

REVOKE TRUNCATE, REFERENCES, TRIGGER ON public.languages, public.translations FROM anon, authenticated;

-- One locale's messages, layered: default locale < language (pt) < exact locale (pt-BR).
-- A half-translated language therefore still renders every string.
--   POST /rest/v1/rpc/get_translations   {"p_locale":"es","p_namespaces":["common","auth"]}
CREATE FUNCTION public.get_translations(p_locale text, p_namespaces text[] DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
  WITH cfg AS (
    SELECT coalesce((SELECT value #>> '{}' FROM public.site_settings WHERE key = 'default_locale'), 'en') AS def
  ),
  wanted(rank, loc) AS (
    SELECT 0, (SELECT def FROM cfg)
    UNION ALL SELECT 1, split_part(p_locale, '-', 1)
    UNION ALL SELECT 2, p_locale
  ),
  hits AS (
    SELECT t.namespace || '.' || t.key AS k, t.value, w.rank
    FROM public.translations t
    JOIN wanted w ON lower(t.locale) = lower(w.loc)
    WHERE p_namespaces IS NULL OR t.namespace = ANY (p_namespaces)
  ),
  best AS (SELECT DISTINCT ON (k) k, value FROM hits ORDER BY k, rank DESC)
  SELECT coalesce(jsonb_object_agg(k, value), '{}'::jsonb) FROM best;
$$;
GRANT EXECUTE ON FUNCTION public.get_translations(text, text[]) TO anon, authenticated;

-- ── Seed: languages ─────────────────────────────────────────────────────────
INSERT INTO public.languages (code, name, native_name, direction, is_default) VALUES
  ('en', 'English', 'English', 'ltr', true),
  ('es', 'Spanish', 'Español', 'ltr', false)
ON CONFLICT (code) DO NOTHING;

-- ── Seed: core UI strings ───────────────────────────────────────────────────
INSERT INTO public.translations (locale, namespace, key, value) VALUES
  -- common
  ('en','common','save','Save'),            ('es','common','save','Guardar'),
  ('en','common','cancel','Cancel'),        ('es','common','cancel','Cancelar'),
  ('en','common','delete','Delete'),        ('es','common','delete','Eliminar'),
  ('en','common','edit','Edit'),            ('es','common','edit','Editar'),
  ('en','common','create','Create'),        ('es','common','create','Crear'),
  ('en','common','close','Close'),          ('es','common','close','Cerrar'),
  ('en','common','search','Search'),        ('es','common','search','Buscar'),
  ('en','common','loading','Loading…'),     ('es','common','loading','Cargando…'),
  ('en','common','retry','Try again'),      ('es','common','retry','Reintentar'),
  ('en','common','back','Back'),            ('es','common','back','Atrás'),
  ('en','common','next','Next'),            ('es','common','next','Siguiente'),
  ('en','common','confirm','Confirm'),      ('es','common','confirm','Confirmar'),
  ('en','common','yes','Yes'),              ('es','common','yes','Sí'),
  ('en','common','no','No'),                ('es','common','no','No'),
  ('en','common','submit','Submit'),        ('es','common','submit','Enviar'),
  ('en','common','more','More'),            ('es','common','more','Más'),
  ('en','common','items_one','{count} item'),   ('es','common','items_one','{count} elemento'),
  ('en','common','items_other','{count} items'),('es','common','items_other','{count} elementos'),
  -- auth
  ('en','auth','sign_in','Sign in'),                    ('es','auth','sign_in','Iniciar sesión'),
  ('en','auth','sign_out','Sign out'),                  ('es','auth','sign_out','Cerrar sesión'),
  ('en','auth','sign_up','Create account'),             ('es','auth','sign_up','Crear cuenta'),
  ('en','auth','email','Email'),                        ('es','auth','email','Correo electrónico'),
  ('en','auth','password','Password'),                  ('es','auth','password','Contraseña'),
  ('en','auth','forgot_password','Forgot your password?'), ('es','auth','forgot_password','¿Olvidaste tu contraseña?'),
  ('en','auth','welcome_back','Welcome back, {name}'),  ('es','auth','welcome_back','Bienvenido de nuevo, {name}'),
  -- nav
  ('en','nav','home','Home'),              ('es','nav','home','Inicio'),
  ('en','nav','dashboard','Dashboard'),    ('es','nav','dashboard','Panel'),
  ('en','nav','settings','Settings'),      ('es','nav','settings','Ajustes'),
  ('en','nav','profile','Profile'),        ('es','nav','profile','Perfil'),
  -- theme
  ('en','theme','label','Theme'),          ('es','theme','label','Tema'),
  ('en','theme','light','Light'),          ('es','theme','light','Claro'),
  ('en','theme','dark','Dark'),            ('es','theme','dark','Oscuro'),
  ('en','theme','system','System'),        ('es','theme','system','Sistema'),
  ('en','theme','choose','Choose a theme'),('es','theme','choose','Elegir tema'),
  -- language picker
  ('en','i18n','language','Language'),               ('es','i18n','language','Idioma'),
  ('en','i18n','choose_language','Choose a language'),('es','i18n','choose_language','Elegir idioma'),
  -- errors
  ('en','errors','generic','Something went wrong. Please try again.'), ('es','errors','generic','Algo salió mal. Inténtalo de nuevo.'),
  ('en','errors','not_found','We could not find that page.'),          ('es','errors','not_found','No se encontró la página.'),
  ('en','errors','unauthorized','You do not have permission to view this.'), ('es','errors','unauthorized','No tienes permiso para ver esto.'),
  ('en','errors','network','Network error. Check your connection.'),   ('es','errors','network','Error de red. Comprueba tu conexión.')
ON CONFLICT (locale, namespace, key) DO NOTHING;

COMMIT;
