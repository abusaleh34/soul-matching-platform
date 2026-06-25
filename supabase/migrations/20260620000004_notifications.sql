-- ====================================================================
-- Migration 0004 — Multi-Trigger Notification Engine
-- --------------------------------------------------------------------
-- BRD §3.4:
--   * matches INSERT  -> notify BOTH users, payload "تم ربط التوافق الروحي بنجاح!"
--   * messages INSERT -> notify the RECIPIENT ONLY.
-- Both triggers are SECURITY DEFINER so they can write notifications while
-- the notifications table is locked down by RLS (BRD §4.2).
-- ====================================================================

-- 1. Match success -> both paired users
CREATE OR REPLACE FUNCTION public.create_match_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.notifications (user_id, title, body, type, match_id)
    VALUES
        (NEW.user1_id, 'تم ربط التوافق الروحي بنجاح!',
         'تهانينا، تم العثور على شريك متوافق معك وبدأت غرفة التركيز.', 'match', NEW.id),
        (NEW.user2_id, 'تم ربط التوافق الروحي بنجاح!',
         'تهانينا، تم العثور على شريك متوافق معك وبدأت غرفة التركيز.', 'match', NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS match_notification_trigger ON public.matches;
CREATE TRIGGER match_notification_trigger
    AFTER INSERT ON public.matches
    FOR EACH ROW
    EXECUTE FUNCTION public.create_match_notifications();

-- 2. New message -> recipient only (never the sender)
CREATE OR REPLACE FUNCTION public.create_message_notifications()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user1_id     UUID;
    v_user2_id     UUID;
    v_recipient_id UUID;
BEGIN
    SELECT user1_id, user2_id INTO v_user1_id, v_user2_id
    FROM public.matches
    WHERE id = NEW.match_id;

    IF NEW.sender_id = v_user1_id THEN
        v_recipient_id := v_user2_id;
    ELSE
        v_recipient_id := v_user1_id;
    END IF;

    IF v_recipient_id IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, title, body, type, match_id)
        VALUES (v_recipient_id, 'لديك رسالة جديدة',
                'لديك رسالة جديدة في غرفة التركيز', 'message', NEW.match_id);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS message_notification_trigger ON public.messages;
CREATE TRIGGER message_notification_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.create_message_notifications();
