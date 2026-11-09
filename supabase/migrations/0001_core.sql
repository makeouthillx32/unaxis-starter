-- 0001_core.sql — blank core baseline (generated; do not hand-edit)
-- Core tables only: no data, no commerce or app-specific objects, no hard-coded project URLs.
-- Apply to an EMPTY Supabase instance once; the instance's own auth/storage schemas
-- come from the Supabase template.

BEGIN;
-- SQL-language functions (is_admin) reference tables created further down.
SET LOCAL check_function_bodies = off;

-- ── types ─────────────────────────────────────────────────────────────
CREATE TYPE public.zone_lifecycle_state AS ENUM ('active', 'missing', 'archived');
CREATE TYPE public.zone_public_status AS ENUM ('online', 'degraded', 'offline', 'unknown', 'stale');
CREATE TYPE public.zone_visibility AS ENUM ('private', 'unlisted', 'public');

-- ── functions ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$function$;

CREATE OR REPLACE FUNCTION public.update_themes_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.touch_site_assets_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$function$;

CREATE OR REPLACE FUNCTION public.guard_profile_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- The service role is server-side administration; leave it alone.
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  -- An existing admin may hand out roles.
  if public.is_admin() then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- Silently pin the role back rather than raising: callers legitimately
    -- send whole-row updates, and failing those would break profile editing.
    if new.role is distinct from old.role then
      new.role := old.role;
    end if;

  elsif tg_op = 'INSERT' then
    -- Only the privileged roles are clamped. Signup flows that legitimately
    -- create 'member' or 'researcher' rows keep working untouched.
    if new.role in ('admin', 'moderator') then
      new.role := 'member';
    end if;
  end if;

  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, auth_user_id, email, role, is_active, display_name)
  VALUES (
    NEW.id,
    NEW.id,
    NEW.email,
    'member',
    true,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;

-- ── tables, constraints, indexes, policies, triggers ──────────────────
--
-- Name: admin_audit_log; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.admin_audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_profile_id uuid,
    actor_auth_user_id uuid,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    reason text,
    ip inet,
    user_agent text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.profiles (
    id uuid NOT NULL,
    role text DEFAULT 'member'::text,
    avatar_url text,
    initials character varying(10),
    display_name text,
    first_name text,
    last_name text,
    region text DEFAULT 'US'::text,
    email text,
    created_at timestamp with time zone DEFAULT now(),
    last_seen_at timestamp with time zone,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    auth_user_id uuid,
    delete_reason text,
    is_active boolean DEFAULT true NOT NULL,
    deleted_by_auth_user_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    terms_accepted_at timestamp with time zone,
    research_terms_accepted_at timestamp with time zone,
    auth_provider text DEFAULT 'email'::text,
    verified_via text DEFAULT 'unverified'::text,
    clearance_level integer DEFAULT 1,
    CONSTRAINT profiles_region_check CHECK (((region IS NULL) OR (region = ANY (ARRAY['US'::text, 'EU'::text, 'UK'::text, 'CA'::text, 'AU'::text, 'NZ'::text, 'JP'::text, 'IN'::text, 'ROW'::text])))),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'moderator'::text, 'member'::text, 'guest'::text])))
);

--
-- Name: COLUMN profiles.initials; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.profiles.initials IS 'Coach initials for quick hour logging (e.g., TB, SC, GC)';

--
-- Name: hero_slides; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.hero_slides (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_name text DEFAULT 'hero-images'::text NOT NULL,
    object_path text NOT NULL,
    alt_text text,
    pill_text text,
    headline_line1 text NOT NULL,
    headline_line2 text,
    subtext text,
    primary_button_label text DEFAULT 'Shop Now'::text NOT NULL,
    primary_button_href text DEFAULT '/shop'::text NOT NULL,
    secondary_button_label text,
    secondary_button_href text,
    text_alignment text DEFAULT 'left'::text NOT NULL,
    text_color text DEFAULT 'dark'::text NOT NULL,
    overlay_opacity numeric(3,2) DEFAULT 0.3,
    "position" integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    blurhash text,
    width integer DEFAULT 2880,
    height integer DEFAULT 1050,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    mobile_bucket_name text DEFAULT 'hero-images'::text NOT NULL,
    mobile_object_path text,
    mobile_alt_text text,
    mobile_width integer,
    mobile_height integer,
    target_device text DEFAULT 'all'::text,
    page text DEFAULT 'shop'::text NOT NULL,
    show_overlay boolean DEFAULT false NOT NULL,
    cta_alignment text DEFAULT 'inherit'::text NOT NULL,
    cta_underline boolean DEFAULT false NOT NULL,
    overlay_position text DEFAULT 'center'::text NOT NULL,
    overlay_pad_x integer DEFAULT 24 NOT NULL,
    overlay_pad_y integer DEFAULT 24 NOT NULL,
    cta_style text DEFAULT 'button'::text NOT NULL,
    text_color_token text,
    CONSTRAINT hero_slides_cta_alignment_chk CHECK ((cta_alignment = ANY (ARRAY['inherit'::text, 'left'::text, 'center'::text, 'right'::text]))),
    CONSTRAINT hero_slides_cta_style_chk CHECK ((cta_style = ANY (ARRAY['button'::text, 'text'::text]))),
    CONSTRAINT hero_slides_overlay_opacity_check CHECK (((overlay_opacity >= (0)::numeric) AND (overlay_opacity <= (1)::numeric))),
    CONSTRAINT hero_slides_overlay_pad_chk CHECK ((((overlay_pad_x >= 0) AND (overlay_pad_x <= 400)) AND ((overlay_pad_y >= 0) AND (overlay_pad_y <= 400)))),
    CONSTRAINT hero_slides_overlay_position_chk CHECK ((overlay_position = ANY (ARRAY['top'::text, 'center'::text, 'bottom'::text]))),
    CONSTRAINT hero_slides_text_alignment_check CHECK ((text_alignment = ANY (ARRAY['left'::text, 'center'::text, 'right'::text]))),
    CONSTRAINT hero_slides_text_color_check CHECK ((text_color = ANY (ARRAY['dark'::text, 'light'::text]))),
    CONSTRAINT hero_slides_text_color_token_chk CHECK (((text_color_token IS NULL) OR (text_color_token = ANY (ARRAY['foreground'::text, 'primary'::text, 'accent'::text, 'muted-foreground'::text, 'card-foreground'::text, 'destructive'::text, 'background'::text]))))
);

--
-- Name: TABLE hero_slides; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON TABLE public.hero_slides IS 'Modern hero carousel system. Replaces old single-image home_hero table.';

--
-- Name: COLUMN hero_slides.mobile_object_path; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.mobile_object_path IS 'Optional mobile hero image (portrait). If null, desktop object_path is used on mobile.';

--
-- Name: COLUMN hero_slides.show_overlay; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.show_overlay IS 'Render the text/CTA overlay (pill, headline, subtext, buttons) on top of the image. False = image-only, the pre-2026-09-05 behaviour.';

--
-- Name: COLUMN hero_slides.cta_alignment; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.cta_alignment IS 'Horizontal placement of the CTA buttons. "inherit" follows text_alignment.';

--
-- Name: COLUMN hero_slides.cta_underline; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.cta_underline IS 'Underline the CTA button labels.';

--
-- Name: COLUMN hero_slides.overlay_position; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.overlay_position IS 'Vertical anchor for the text/CTA overlay: top | center | bottom.';

--
-- Name: COLUMN hero_slides.overlay_pad_x; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.overlay_pad_x IS 'Horizontal inset in px. Applied identically on desktop and mobile so the position you set is the position that ships.';

--
-- Name: COLUMN hero_slides.overlay_pad_y; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.overlay_pad_y IS 'Vertical inset in px from the anchored edge.';

--
-- Name: COLUMN hero_slides.cta_style; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.cta_style IS 'button = filled pill (default). text = plain type, no background or border, so it sits on artwork that already accounts for the label.';

--
-- Name: COLUMN hero_slides.text_color_token; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.hero_slides.text_color_token IS 'Theme CSS variable for overlay text, e.g. "primary" -> hsl(var(--primary)). NULL keeps the black/white default from text_color.';

--
-- Name: homepage_content; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.homepage_content (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    json jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: invites; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.invites (
    code uuid DEFAULT gen_random_uuid() NOT NULL,
    role_id text,
    created_at timestamp with time zone DEFAULT now(),
    inviter_id uuid,
    max_uses integer DEFAULT 1 NOT NULL,
    expires_at timestamp with time zone
);

--
-- Name: landing_nav_items; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.landing_nav_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{"de": "", "en": ""}'::jsonb NOT NULL,
    path text,
    submenu_type text,
    "position" integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    open_in_new_tab boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

--
-- Name: landing_sections; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.landing_sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    "position" integer NOT NULL,
    type text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    config jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    page text DEFAULT 'shop'::text NOT NULL
);

--
-- Name: TABLE landing_sections; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON TABLE public.landing_sections IS 'Dynamic landing page section configuration';

--
-- Name: COLUMN landing_sections."position"; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.landing_sections."position" IS 'Display order on landing page (1, 2, 3...)';

--
-- Name: COLUMN landing_sections.type; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.landing_sections.type IS 'Section type: top_banner, hero_carousel, categories_grid, static_html, products_grid';

--
-- Name: COLUMN landing_sections.is_active; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.landing_sections.is_active IS 'Whether this section is currently displayed';

--
-- Name: COLUMN landing_sections.config; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.landing_sections.config IS 'JSON configuration specific to each section type';

--
-- Name: nav_items; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.nav_items (
    id bigint NOT NULL,
    label text NOT NULL,
    page_slug text NOT NULL,
    parent_id bigint,
    sort_order integer NOT NULL
);

--
-- Name: nav_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
CREATE SEQUENCE public.nav_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: nav_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--
ALTER SEQUENCE public.nav_items_id_seq OWNED BY public.nav_items.id;

--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid,
    receiver_id uuid,
    title text NOT NULL,
    content text,
    image_url text,
    action_url text,
    created_at timestamp with time zone DEFAULT now(),
    role_admin boolean DEFAULT false,
    role_jobcoach boolean DEFAULT false,
    role_client boolean DEFAULT false,
    role_user boolean DEFAULT false,
    type text DEFAULT 'generic'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_read boolean DEFAULT false NOT NULL
);

--
-- Name: page_blocks; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.page_blocks (
    id bigint NOT NULL,
    page_slug text NOT NULL,
    sort_order integer NOT NULL,
    block_type text NOT NULL,
    content text,
    image_src text,
    alt_text text,
    props_json jsonb
);

--
-- Name: page_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
CREATE SEQUENCE public.page_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: page_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--
ALTER SEQUENCE public.page_blocks_id_seq OWNED BY public.page_blocks.id;

--
-- Name: page_widgets; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.page_widgets (
    id bigint NOT NULL,
    page_slug text NOT NULL,
    sort_order integer NOT NULL,
    widget_type text NOT NULL,
    widget_config jsonb NOT NULL
);

--
-- Name: page_widgets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
CREATE SEQUENCE public.page_widgets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: page_widgets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--
ALTER SEQUENCE public.page_widgets_id_seq OWNED BY public.page_widgets.id;

--
-- Name: pages; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.pages (
    slug text NOT NULL,
    title text NOT NULL,
    parent_slug text,
    anchor_id text,
    template text DEFAULT 'standard'::text NOT NULL,
    back_label text
);

--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.roles (
    id text NOT NULL,
    role text NOT NULL,
    color text
);

--
-- Name: COLUMN roles.color; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.roles.color IS 'Hex color code (e.g. #FF5733) for visual representation of this role';

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.schema_migrations (
    version character varying(14) NOT NULL
);

--
-- Name: site_assets; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.site_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scope text NOT NULL,
    asset_key text NOT NULL,
    kind text NOT NULL,
    storage_bucket text DEFAULT 'landing-assets'::text NOT NULL,
    storage_path text NOT NULL,
    public_url text NOT NULL,
    format text,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE site_assets; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON TABLE public.site_assets IS 'Hot-swappable site asset registry. Resolver falls back to a bundled/known URL when a key is absent or inactive, so a missing row is never a broken page.';

--
-- Name: site_banner_group_items; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.site_banner_group_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    group_id uuid NOT NULL,
    text text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: site_banner_groups; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.site_banner_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    banner_id uuid NOT NULL,
    label text,
    is_enabled boolean DEFAULT true NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    text text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    active_days smallint[],
    start_time time without time zone,
    end_time time without time zone,
    start_date date,
    end_date date,
    timezone text DEFAULT 'America/Chicago'::text NOT NULL
);

--
-- Name: site_banner_items; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.site_banner_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    banner_id uuid NOT NULL,
    text text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);

--
-- Name: site_banners; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.site_banners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    display_mode text DEFAULT 'static'::text NOT NULL,
    animation_speed_ms integer DEFAULT 450 NOT NULL,
    rotation_interval_ms integer DEFAULT 2200 NOT NULL,
    pause_on_hover boolean DEFAULT true NOT NULL,
    separator text DEFAULT ' • '::text NOT NULL
);

--
-- Name: static_pages; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.static_pages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    content_format text DEFAULT 'html'::text NOT NULL,
    meta_description text,
    meta_keywords text[],
    og_image_url text,
    is_published boolean DEFAULT true NOT NULL,
    published_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    zone_key text NOT NULL,
    CONSTRAINT static_pages_content_format_check CHECK ((content_format = ANY (ARRAY['html'::text, 'markdown'::text])))
);

--
-- Name: TABLE static_pages; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON TABLE public.static_pages IS 'Legal and brand pages for Desert Cowgirl boutique (Privacy, Terms, About Us).';

--
-- Name: COLUMN static_pages.zone_key; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.static_pages.zone_key IS 'Zone (public.zones.key) this page belongs to. Pages resolve by (zone_key, slug); a zone never falls back to another zone''s row.';

--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.team_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    image_url text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: themes; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.themes (
    id text NOT NULL,
    name text NOT NULL,
    description text,
    preview_color text,
    theme_data jsonb NOT NULL,
    is_system boolean DEFAULT true,
    created_by uuid,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    version integer DEFAULT 1,
    is_active boolean DEFAULT true,
    tags text[],
    download_count integer DEFAULT 0,
    meta_data jsonb DEFAULT '{}'::jsonb
);

--
-- Name: zone_audit_events; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zone_audit_events (
    id bigint NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL,
    actor text,
    action text NOT NULL,
    zone_key text,
    before jsonb,
    after jsonb,
    payload_version text,
    source text
);

--
-- Name: zone_audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
ALTER TABLE public.zone_audit_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.zone_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: zone_deployments; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zone_deployments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    zone_key text NOT NULL,
    env_id text NOT NULL,
    role text DEFAULT 'primary'::text NOT NULL,
    container_state text,
    deployed_revision text,
    image_digest text,
    last_deploy_at timestamp with time zone,
    last_proxy_verified_at timestamp with time zone,
    observed_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: zone_endpoint_checks; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zone_endpoint_checks (
    id bigint NOT NULL,
    zone_key text NOT NULL,
    http_status integer,
    response_time_ms integer,
    ok boolean,
    failure_reason text,
    checked_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: zone_endpoint_checks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
ALTER TABLE public.zone_endpoint_checks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.zone_endpoint_checks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: zone_endpoint_status; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zone_endpoint_status (
    zone_key text NOT NULL,
    public_status public.zone_public_status DEFAULT 'unknown'::public.zone_public_status NOT NULL,
    http_status integer,
    response_time_ms integer,
    checked_at timestamp with time zone,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    failure_reason text
);

--
-- Name: zone_sync_runs; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zone_sync_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    actor text,
    source text DEFAULT 'unaxis'::text NOT NULL,
    dry_run boolean DEFAULT false NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    updated_count integer DEFAULT 0 NOT NULL,
    missing_count integer DEFAULT 0 NOT NULL,
    conflict_count integer DEFAULT 0 NOT NULL,
    warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    result text
);

--
-- Name: zones; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE public.zones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    label text NOT NULL,
    domain text NOT NULL,
    service text NOT NULL,
    container text NOT NULL,
    image text NOT NULL,
    dockerfile text,
    upstream_env_key text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    environment_id uuid,
    footer_pinned boolean DEFAULT false NOT NULL,
    description text,
    image_url text,
    visibility public.zone_visibility DEFAULT 'private'::public.zone_visibility NOT NULL,
    lifecycle_state public.zone_lifecycle_state DEFAULT 'active'::public.zone_lifecycle_state NOT NULL,
    show_in_footer boolean DEFAULT false NOT NULL,
    show_in_directory boolean DEFAULT false NOT NULL,
    include_in_sitemap boolean DEFAULT false NOT NULL,
    health_path text DEFAULT '/'::text NOT NULL,
    expected_status integer DEFAULT 200 NOT NULL,
    source text DEFAULT 'unaxis'::text NOT NULL,
    last_synced_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    og_image_bucket text,
    og_image_path text,
    og_image_alt text,
    og_image_updated_at timestamp with time zone,
    og_image_width integer,
    og_image_height integer,
    og_image_bytes bigint,
    og_image_mime_type text,
    og_image_original_name text,
    og_image_source_width integer,
    og_image_source_height integer,
    site_icon_bucket text,
    site_icon_path text,
    site_icon_updated_at timestamp with time zone,
    site_icon_original_name text,
    site_icon_source_width integer,
    site_icon_source_height integer,
    site_icon_bytes bigint
);

--
-- Name: COLUMN zones.environment_id; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.environment_id IS 'Which environment (machine/endpoint) this zone is deployed to. NULL = unassigned. Set at scaffold time or via the UNAXIS env panel.';

--
-- Name: COLUMN zones.footer_pinned; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.footer_pinned IS 'Controls whether this app is shown in the public landing footer links.';

--
-- Name: COLUMN zones.og_image_bucket; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_bucket IS 'Dashboard-owned Supabase Storage bucket containing this site OpenGraph image.';

--
-- Name: COLUMN zones.og_image_path; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_path IS 'Dashboard-owned object path for this site OpenGraph image.';

--
-- Name: COLUMN zones.og_image_alt; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_alt IS 'Accessible description used for OpenGraph and Twitter image metadata.';

--
-- Name: COLUMN zones.og_image_updated_at; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_updated_at IS 'Cache-busting timestamp for this site OpenGraph image.';

--
-- Name: COLUMN zones.og_image_width; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_width IS 'Rendered OpenGraph image width in pixels.';

--
-- Name: COLUMN zones.og_image_height; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_height IS 'Rendered OpenGraph image height in pixels.';

--
-- Name: COLUMN zones.og_image_bytes; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_bytes IS 'Rendered OpenGraph object size in bytes.';

--
-- Name: COLUMN zones.og_image_mime_type; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_mime_type IS 'Rendered OpenGraph object MIME type.';

--
-- Name: COLUMN zones.og_image_original_name; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_original_name IS 'Original uploaded filename retained for dashboard display.';

--
-- Name: COLUMN zones.og_image_source_width; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_source_width IS 'Source upload width before OpenGraph rendering.';

--
-- Name: COLUMN zones.og_image_source_height; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.og_image_source_height IS 'Source upload height before OpenGraph rendering.';

--
-- Name: COLUMN zones.site_icon_bucket; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_bucket IS 'Dashboard-owned Supabase Storage bucket containing this site icon set.';

--
-- Name: COLUMN zones.site_icon_path; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_path IS 'Versioned Storage path prefix containing the rendered site icon variants.';

--
-- Name: COLUMN zones.site_icon_updated_at; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_updated_at IS 'Cache-busting timestamp for this site icon set.';

--
-- Name: COLUMN zones.site_icon_original_name; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_original_name IS 'Original uploaded icon filename retained for dashboard display.';

--
-- Name: COLUMN zones.site_icon_source_width; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_source_width IS 'Source upload width before square site icon rendering.';

--
-- Name: COLUMN zones.site_icon_source_height; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_source_height IS 'Source upload height before square site icon rendering.';

--
-- Name: COLUMN zones.site_icon_bytes; Type: COMMENT; Schema: public; Owner: -
--
COMMENT ON COLUMN public.zones.site_icon_bytes IS 'Combined byte size of all rendered PNG icon variants.';

--
-- Name: nav_items id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.nav_items ALTER COLUMN id SET DEFAULT nextval('public.nav_items_id_seq'::regclass);

--
-- Name: page_blocks id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_blocks ALTER COLUMN id SET DEFAULT nextval('public.page_blocks_id_seq'::regclass);

--
-- Name: page_widgets id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_widgets ALTER COLUMN id SET DEFAULT nextval('public.page_widgets_id_seq'::regclass);

--
-- Name: admin_audit_log admin_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.admin_audit_log
    ADD CONSTRAINT admin_audit_log_pkey PRIMARY KEY (id);

--
-- Name: hero_slides hero_slides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.hero_slides
    ADD CONSTRAINT hero_slides_pkey PRIMARY KEY (id);

--
-- Name: homepage_content homepage_content_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.homepage_content
    ADD CONSTRAINT homepage_content_key_key UNIQUE (key);

--
-- Name: homepage_content homepage_content_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.homepage_content
    ADD CONSTRAINT homepage_content_pkey PRIMARY KEY (id);

--
-- Name: invites invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_pkey PRIMARY KEY (code);

--
-- Name: landing_nav_items landing_nav_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.landing_nav_items
    ADD CONSTRAINT landing_nav_items_pkey PRIMARY KEY (id);

--
-- Name: landing_sections landing_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.landing_sections
    ADD CONSTRAINT landing_sections_pkey PRIMARY KEY (id);

--
-- Name: nav_items nav_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.nav_items
    ADD CONSTRAINT nav_items_pkey PRIMARY KEY (id);

--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);

--
-- Name: page_blocks page_blocks_page_slug_sort_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_page_slug_sort_order_key UNIQUE (page_slug, sort_order);

--
-- Name: page_blocks page_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_pkey PRIMARY KEY (id);

--
-- Name: page_widgets page_widgets_page_slug_sort_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_widgets
    ADD CONSTRAINT page_widgets_page_slug_sort_order_key UNIQUE (page_slug, sort_order);

--
-- Name: page_widgets page_widgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_widgets
    ADD CONSTRAINT page_widgets_pkey PRIMARY KEY (id);

--
-- Name: pages pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_pkey PRIMARY KEY (slug);

--
-- Name: profiles profiles_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_key UNIQUE (id);

--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);

--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);

--
-- Name: roles roles_role_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_role_key UNIQUE (role);

--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);

--
-- Name: site_assets site_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_assets
    ADD CONSTRAINT site_assets_pkey PRIMARY KEY (id);

--
-- Name: site_banner_group_items site_banner_group_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_group_items
    ADD CONSTRAINT site_banner_group_items_pkey PRIMARY KEY (id);

--
-- Name: site_banner_groups site_banner_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_groups
    ADD CONSTRAINT site_banner_groups_pkey PRIMARY KEY (id);

--
-- Name: site_banner_items site_banner_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_items
    ADD CONSTRAINT site_banner_items_pkey PRIMARY KEY (id);

--
-- Name: site_banners site_banners_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banners
    ADD CONSTRAINT site_banners_key_key UNIQUE (key);

--
-- Name: site_banners site_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banners
    ADD CONSTRAINT site_banners_pkey PRIMARY KEY (id);

--
-- Name: static_pages static_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.static_pages
    ADD CONSTRAINT static_pages_pkey PRIMARY KEY (id);

--
-- Name: static_pages static_pages_zone_key_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.static_pages
    ADD CONSTRAINT static_pages_zone_key_slug_key UNIQUE (zone_key, slug);

--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);

--
-- Name: themes themes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.themes
    ADD CONSTRAINT themes_pkey PRIMARY KEY (id);

--
-- Name: zone_audit_events zone_audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_audit_events
    ADD CONSTRAINT zone_audit_events_pkey PRIMARY KEY (id);

--
-- Name: zone_deployments zone_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_deployments
    ADD CONSTRAINT zone_deployments_pkey PRIMARY KEY (id);

--
-- Name: zone_deployments zone_deployments_zone_key_env_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_deployments
    ADD CONSTRAINT zone_deployments_zone_key_env_id_key UNIQUE (zone_key, env_id);

--
-- Name: zone_endpoint_checks zone_endpoint_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_endpoint_checks
    ADD CONSTRAINT zone_endpoint_checks_pkey PRIMARY KEY (id);

--
-- Name: zone_endpoint_status zone_endpoint_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_endpoint_status
    ADD CONSTRAINT zone_endpoint_status_pkey PRIMARY KEY (zone_key);

--
-- Name: zone_sync_runs zone_sync_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zone_sync_runs
    ADD CONSTRAINT zone_sync_runs_pkey PRIMARY KEY (id);

--
-- Name: zones zones_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zones
    ADD CONSTRAINT zones_key_key UNIQUE (key);

--
-- Name: zones zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.zones
    ADD CONSTRAINT zones_pkey PRIMARY KEY (id);

--
-- Name: admin_audit_log_actor_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX admin_audit_log_actor_idx ON public.admin_audit_log USING btree (actor_auth_user_id);

--
-- Name: admin_audit_log_created_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX admin_audit_log_created_idx ON public.admin_audit_log USING btree (created_at DESC);

--
-- Name: admin_audit_log_entity_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX admin_audit_log_entity_idx ON public.admin_audit_log USING btree (entity_type, entity_id);

--
-- Name: hero_slides_active_position_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX hero_slides_active_position_idx ON public.hero_slides USING btree (is_active, "position");

--
-- Name: idx_hero_slides_page; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_hero_slides_page ON public.hero_slides USING btree (page);

--
-- Name: idx_landing_sections_active; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_landing_sections_active ON public.landing_sections USING btree (is_active) WHERE (is_active = true);

--
-- Name: idx_landing_sections_position; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_landing_sections_position ON public.landing_sections USING btree ("position");

--
-- Name: idx_profiles_display_name; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_profiles_display_name ON public.profiles USING btree (display_name);

--
-- Name: idx_profiles_initials; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_profiles_initials ON public.profiles USING btree (initials);

--
-- Name: idx_team_members_position; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_team_members_position ON public.team_members USING btree ("position") WHERE (is_active = true);

--
-- Name: idx_themes_active; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_active ON public.themes USING btree (is_active) WHERE (is_active = true);

--
-- Name: idx_themes_active_system; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_active_system ON public.themes USING btree (is_active, is_system, created_at DESC);

--
-- Name: idx_themes_created_at; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_created_at ON public.themes USING btree (created_at DESC);

--
-- Name: idx_themes_jsonb; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_jsonb ON public.themes USING gin (theme_data);

--
-- Name: idx_themes_search; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_search ON public.themes USING gin (to_tsvector('english'::regconfig, ((name || ' '::text) || COALESCE(description, ''::text))));

--
-- Name: idx_themes_system; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_system ON public.themes USING btree (is_system);

--
-- Name: idx_themes_user; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX idx_themes_user ON public.themes USING btree (created_by) WHERE (created_by IS NOT NULL);

--
-- Name: landing_nav_items_position_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX landing_nav_items_position_idx ON public.landing_nav_items USING btree ("position");

--
-- Name: landing_sections_page_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX landing_sections_page_idx ON public.landing_sections USING btree (page);

--
-- Name: profiles_auth_user_id_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX profiles_auth_user_id_idx ON public.profiles USING btree (auth_user_id);

--
-- Name: profiles_deleted_at_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX profiles_deleted_at_idx ON public.profiles USING btree (deleted_at);

--
-- Name: schema_migrations_version_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX schema_migrations_version_idx ON public.schema_migrations USING btree (version);

--
-- Name: site_assets_scope_active_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX site_assets_scope_active_idx ON public.site_assets USING btree (scope) WHERE is_active;

--
-- Name: site_assets_scope_key_uniq; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX site_assets_scope_key_uniq ON public.site_assets USING btree (scope, asset_key);

--
-- Name: site_banner_group_items_group_id_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX site_banner_group_items_group_id_idx ON public.site_banner_group_items USING btree (group_id);

--
-- Name: site_banner_groups_banner_id_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX site_banner_groups_banner_id_idx ON public.site_banner_groups USING btree (banner_id);

--
-- Name: site_banner_items_banner_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX site_banner_items_banner_idx ON public.site_banner_items USING btree (banner_id);

--
-- Name: site_banner_items_unique_pos; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX site_banner_items_unique_pos ON public.site_banner_items USING btree (banner_id, "position");

--
-- Name: static_pages_zone_slug_published_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX static_pages_zone_slug_published_idx ON public.static_pages USING btree (zone_key, slug) WHERE (is_published = true);

--
-- Name: zone_deployments_zone_key_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX zone_deployments_zone_key_idx ON public.zone_deployments USING btree (zone_key);

--
-- Name: zone_endpoint_checks_zone_key_idx; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX zone_endpoint_checks_zone_key_idx ON public.zone_endpoint_checks USING btree (zone_key, checked_at DESC);

--
-- Name: profiles guard_profile_role_trg; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER guard_profile_role_trg BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role();

--
-- Name: hero_slides set_hero_slides_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER set_hero_slides_updated_at BEFORE UPDATE ON public.hero_slides FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

--
-- Name: static_pages set_static_pages_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER set_static_pages_updated_at BEFORE UPDATE ON public.static_pages FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

--
-- Name: site_assets site_assets_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER site_assets_touch_updated_at BEFORE UPDATE ON public.site_assets FOR EACH ROW EXECUTE FUNCTION public.touch_site_assets_updated_at();

--
-- Name: team_members trg_team_members_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER trg_team_members_updated_at BEFORE UPDATE ON public.team_members FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

--
-- Name: themes trigger_themes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER trigger_themes_updated_at BEFORE UPDATE ON public.themes FOR EACH ROW EXECUTE FUNCTION public.update_themes_updated_at();

--
-- Name: zones zones_updated_at; Type: TRIGGER; Schema: public; Owner: -
--
CREATE TRIGGER zones_updated_at BEFORE UPDATE ON public.zones FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

--
-- Name: invites invites_inviter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

--
-- Name: invites invites_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE SET NULL;

--
-- Name: nav_items nav_items_page_slug_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.nav_items
    ADD CONSTRAINT nav_items_page_slug_fkey FOREIGN KEY (page_slug) REFERENCES public.pages(slug) ON DELETE CASCADE;

--
-- Name: nav_items nav_items_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.nav_items
    ADD CONSTRAINT nav_items_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.nav_items(id) ON DELETE CASCADE;

--
-- Name: page_blocks page_blocks_page_slug_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_blocks
    ADD CONSTRAINT page_blocks_page_slug_fkey FOREIGN KEY (page_slug) REFERENCES public.pages(slug) ON DELETE CASCADE;

--
-- Name: page_widgets page_widgets_page_slug_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.page_widgets
    ADD CONSTRAINT page_widgets_page_slug_fkey FOREIGN KEY (page_slug) REFERENCES public.pages(slug) ON DELETE CASCADE;

--
-- Name: pages pages_parent_slug_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.pages
    ADD CONSTRAINT pages_parent_slug_fkey FOREIGN KEY (parent_slug) REFERENCES public.pages(slug) ON DELETE SET NULL;

--
-- Name: site_banner_group_items site_banner_group_items_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_group_items
    ADD CONSTRAINT site_banner_group_items_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.site_banner_groups(id) ON DELETE CASCADE;

--
-- Name: site_banner_groups site_banner_groups_banner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_groups
    ADD CONSTRAINT site_banner_groups_banner_id_fkey FOREIGN KEY (banner_id) REFERENCES public.site_banners(id) ON DELETE CASCADE;

--
-- Name: site_banner_items site_banner_items_banner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.site_banner_items
    ADD CONSTRAINT site_banner_items_banner_id_fkey FOREIGN KEY (banner_id) REFERENCES public.site_banners(id) ON DELETE CASCADE;

--
-- Name: static_pages static_pages_zone_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY public.static_pages
    ADD CONSTRAINT static_pages_zone_key_fkey FOREIGN KEY (zone_key) REFERENCES public.zones(key) ON UPDATE CASCADE;

--
-- Name: profiles Allow inserting own profile; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Allow inserting own profile" ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = id));

--
-- Name: hero_slides Authenticated users can delete hero_slides; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can delete hero_slides" ON public.hero_slides FOR DELETE TO authenticated USING (true);

--
-- Name: static_pages Authenticated users can delete pages; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can delete pages" ON public.static_pages FOR DELETE TO authenticated USING (true);

--
-- Name: landing_sections Authenticated users can delete sections; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can delete sections" ON public.landing_sections FOR DELETE TO authenticated USING (true);

--
-- Name: hero_slides Authenticated users can insert hero_slides; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can insert hero_slides" ON public.hero_slides FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: static_pages Authenticated users can insert pages; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can insert pages" ON public.static_pages FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: landing_sections Authenticated users can insert sections; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can insert sections" ON public.landing_sections FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: landing_sections Authenticated users can read all sections; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can read all sections" ON public.landing_sections FOR SELECT TO authenticated USING (true);

--
-- Name: hero_slides Authenticated users can update hero_slides; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can update hero_slides" ON public.hero_slides FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

--
-- Name: static_pages Authenticated users can update pages; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can update pages" ON public.static_pages FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

--
-- Name: landing_sections Authenticated users can update sections; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Authenticated users can update sections" ON public.landing_sections FOR UPDATE TO authenticated USING (true);

--
-- Name: hero_slides Public can view hero_slides; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Public can view hero_slides" ON public.hero_slides FOR SELECT USING (true);

--
-- Name: static_pages Public can view published pages; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Public can view published pages" ON public.static_pages FOR SELECT USING ((is_published = true));

--
-- Name: landing_sections Public read access to active sections; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Public read access to active sections" ON public.landing_sections FOR SELECT USING ((is_active = true));

--
-- Name: profiles Users can read their profile; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Users can read their profile" ON public.profiles FOR SELECT USING ((auth.uid() = id));

--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));

--
-- Name: team_members admin_write_team_members; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY admin_write_team_members ON public.team_members USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'editor'::text]))))));

--
-- Name: roles authenticated_read_roles; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY authenticated_read_roles ON public.roles FOR SELECT USING ((( SELECT auth.role() AS role) = 'authenticated'::text));

--
-- Name: hero_slides; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.hero_slides ENABLE ROW LEVEL SECURITY;

--
-- Name: invites; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.invites ENABLE ROW LEVEL SECURITY;

--
-- Name: landing_nav_items landing_nav_auth_write; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY landing_nav_auth_write ON public.landing_nav_items USING ((auth.role() = 'authenticated'::text));

--
-- Name: landing_nav_items; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.landing_nav_items ENABLE ROW LEVEL SECURITY;

--
-- Name: landing_nav_items landing_nav_public_read; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY landing_nav_public_read ON public.landing_nav_items FOR SELECT USING (true);

--
-- Name: landing_sections; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.landing_sections ENABLE ROW LEVEL SECURITY;

--
-- Name: team_members public_read_team_members; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY public_read_team_members ON public.team_members FOR SELECT USING ((is_active = true));

--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: invites service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.invites USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: roles service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.roles USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zone_audit_events service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zone_audit_events USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zone_deployments service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zone_deployments USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zone_endpoint_checks service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zone_endpoint_checks USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zone_endpoint_status service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zone_endpoint_status USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zone_sync_runs service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zone_sync_runs USING ((( SELECT auth.role() AS role) = 'service_role'::text)) WITH CHECK ((( SELECT auth.role() AS role) = 'service_role'::text));

--
-- Name: zones service_key_full_access; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY service_key_full_access ON public.zones USING ((auth.role() = 'service_role'::text)) WITH CHECK ((auth.role() = 'service_role'::text));

--
-- Name: site_assets; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.site_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: site_assets site_assets_admin_write; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY site_assets_admin_write ON public.site_assets USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));

--
-- Name: site_assets site_assets_public_read; Type: POLICY; Schema: public; Owner: -
--
CREATE POLICY site_assets_public_read ON public.site_assets FOR SELECT USING (is_active);

--
-- Name: team_members; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

--
-- Name: zone_audit_events; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zone_audit_events ENABLE ROW LEVEL SECURITY;

--
-- Name: zone_deployments; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zone_deployments ENABLE ROW LEVEL SECURITY;

--
-- Name: zone_endpoint_checks; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zone_endpoint_checks ENABLE ROW LEVEL SECURITY;

--
-- Name: zone_endpoint_status; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zone_endpoint_status ENABLE ROW LEVEL SECURITY;

--
-- Name: zone_sync_runs; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zone_sync_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: zones; Type: ROW SECURITY; Schema: public; Owner: -
--
ALTER TABLE public.zones ENABLE ROW LEVEL SECURITY;

-- ── signup: every new auth user gets a profile ────────────────────────
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── seed: core roles ──────────────────────────────────────────────────
INSERT INTO public.roles (id, role, color) VALUES ('admin', 'admin', '#7c2d12'), ('member', 'member', '#92400e'), ('guest', 'guest', '#78716c') ON CONFLICT DO NOTHING;

-- ── seed: core storage buckets ────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('avatars', 'avatars', true, 52428800, NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('attachments', 'attachments', true, 52428800, NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('hero-images', 'hero-images', true, 52428800, NULL) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('site-assets', 'site-assets', true, 8388608, ARRAY['image/jpeg', 'image/png', 'image/webp']) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('landing-assets', 'landing-assets', true, 33554432, ARRAY['video/mp4', 'video/webm', 'image/webp', 'image/png', 'image/jpeg', 'image/avif', 'image/svg+xml', 'model/gltf-binary', 'model/gltf+json', 'application/octet-stream']) ON CONFLICT (id) DO NOTHING;

COMMIT;
