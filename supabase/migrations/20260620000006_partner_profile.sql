-- ====================================================================
-- Migration 0006 — Partner profile data minimisation
-- --------------------------------------------------------------------
-- Audit finding (Major): the broad `profiles_select_partner` policy + full
-- table SELECT grant let a matched user read EVERY column of their partner —
-- including questionnaire_answers, psychological_profile and is_admin.
--
-- Fix: remove direct partner row access and expose ONLY the display columns
-- through a SECURITY DEFINER function. Users keep full read of their OWN row;
-- partners are reachable solely via get_partner_profile(match_id), which never
-- returns sensitive/internal columns and is future-proof (new columns are not
-- leaked unless explicitly added to the projection here).
-- ====================================================================

-- Remove the broad partner read policy (own-profile policy is retained).
DROP POLICY IF EXISTS profiles_select_partner ON public.profiles;

-- Safe, explicit partner projection for an active match the caller belongs to.
CREATE OR REPLACE FUNCTION public.get_partner_profile(p_match_id UUID)
RETURNS TABLE (
    id                UUID,
    first_name        TEXT,
    age               INTEGER,
    city              TEXT,
    country           TEXT,
    marital_status    TEXT,
    height            INTEGER,
    body_type         TEXT,
    education_level   TEXT,
    employment_status TEXT,
    smoking_habit     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_me      UUID := (SELECT auth.uid());
    v_partner UUID;
BEGIN
    SELECT CASE
               WHEN m.user1_id = v_me THEN m.user2_id
               WHEN m.user2_id = v_me THEN m.user1_id
           END
    INTO v_partner
    FROM public.matches m
    WHERE m.id = p_match_id;

    IF v_partner IS NULL THEN
        RETURN;  -- caller is not a participant of this match
    END IF;

    RETURN QUERY
        SELECT p.id, p.first_name, p.age, p.city, p.country, p.marital_status,
               p.height, p.body_type, p.education_level, p.employment_status,
               p.smoking_habit
        FROM public.profiles p
        WHERE p.id = v_partner;
END;
$$;

REVOKE ALL ON FUNCTION public.get_partner_profile(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_partner_profile(UUID) TO authenticated;
