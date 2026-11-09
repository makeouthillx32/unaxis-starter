-- 0002_security.sql — secure by default
--
-- Supabase grants the `anon` and `authenticated` roles full privileges on every
-- new table in `public`, so a table WITHOUT row level security is readable and
-- writable by anyone holding the anon key — and the anon key is public (it is
-- baked into every client bundle). 0001 creates 15 such tables. This migration
-- turns RLS on for all of them and states, per table, who may do what.
--
-- Rules the core follows (keep them when you add tables):
--   1. Every table in `public` has RLS enabled. No exceptions.
--   2. Public site content: readable by everyone, writable by admins only.
--   3. Personal data (profiles, notifications): own rows only, plus admins.
--   4. System tables (audit log, migrations): no client access at all.
--   5. The service role bypasses RLS and is used only server-side.
--
-- Admin = public.is_admin() (a profile with role 'admin').

BEGIN;

-- ── 1. No client role needs these on any table ──────────────────────────────
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon, authenticated;

-- ── 2. Public site content: read by all, written by admins ─────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'pages', 'page_blocks', 'page_widgets', 'nav_items', 'homepage_content',
    'site_banners', 'site_banner_groups', 'site_banner_group_items', 'site_banner_items'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY public_read ON public.%I FOR SELECT TO anon, authenticated USING (true)', t);
    EXECUTE format('CREATE POLICY admin_write ON public.%I FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())', t);
  END LOOP;
END $$;

-- Themes: everyone reads the active ones; admins manage all.
ALTER TABLE public.themes ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read_active ON public.themes FOR SELECT TO anon, authenticated USING (is_active IS NOT FALSE);
CREATE POLICY admin_all ON public.themes FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Static pages: the public sees published pages only; admins see and edit drafts.
ALTER TABLE public.static_pages ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read_published ON public.static_pages FOR SELECT TO anon, authenticated USING (is_published IS TRUE);
CREATE POLICY admin_all ON public.static_pages FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 3. Personal data ────────────────────────────────────────────────────────
-- Profiles: a user reads and edits their own row (the guard_profile_role trigger
-- stops them promoting themselves); admins do everything. Rows are created by the
-- signup trigger (SECURITY DEFINER), never by a client, so there is no INSERT policy.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_read ON public.profiles FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR auth_user_id = (SELECT auth.uid()) OR public.is_admin());
CREATE POLICY own_update ON public.profiles FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid()) OR auth_user_id = (SELECT auth.uid()) OR public.is_admin())
  WITH CHECK (id = (SELECT auth.uid()) OR auth_user_id = (SELECT auth.uid()) OR public.is_admin());
CREATE POLICY admin_delete ON public.profiles FOR DELETE TO authenticated USING (public.is_admin());

-- Notifications: the receiver and the sender can read; the receiver can mark read;
-- admins manage everything.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY party_read ON public.notifications FOR SELECT TO authenticated
  USING (receiver_id = (SELECT auth.uid()) OR sender_id = (SELECT auth.uid()) OR public.is_admin());
CREATE POLICY receiver_update ON public.notifications FOR UPDATE TO authenticated
  USING (receiver_id = (SELECT auth.uid())) WITH CHECK (receiver_id = (SELECT auth.uid()));
CREATE POLICY admin_all ON public.notifications FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 4. System tables: no client access ─────────────────────────────────────
-- Admins can read the audit log; nothing writes it except the service role.
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_read ON public.admin_audit_log FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.admin_audit_log FROM anon, authenticated;

-- Migration bookkeeping is for the migration runner only.
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.schema_migrations FROM anon, authenticated;

COMMIT;
