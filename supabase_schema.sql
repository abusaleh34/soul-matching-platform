-- ====================================================================
-- Database Migration: Soul Matching Platform Production Suite
-- ====================================================================

-- 1. Create Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on notifications table
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Allow users to see only their own notifications
CREATE POLICY "Users can view their own notifications" 
ON public.notifications 
FOR SELECT 
USING (auth.uid() = user_id);

-- Allow users to update only their own notifications (e.g., mark as read)
CREATE POLICY "Users can update their own notifications" 
ON public.notifications 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Allow system/service role to bypass RLS (automatic)

-- 2. Add is_admin column to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;


-- 3. Trigger for Match Notifications
-- Triggers when a new match is created and inserts notification rows for both users.
CREATE OR REPLACE FUNCTION public.create_match_notifications()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert notification for User 1
    INSERT INTO public.notifications (user_id, title, body)
    VALUES (NEW.user1_id, 'تم العثور على شريك جديد!', 'تهانينا، تم العثور على شريك متوافق معك وبدء غرفة التعارف المبدئي!');

    -- Insert notification for User 2
    INSERT INTO public.notifications (user_id, title, body)
    VALUES (NEW.user2_id, 'تم العثور على شريك جديد!', 'تهانينا، تم العثور على شريك متوافق معك وبدء غرفة التعارف المبدئي!');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER match_notification_trigger
AFTER INSERT ON public.matches
FOR EACH ROW
EXECUTE FUNCTION public.create_match_notifications();


-- 4. Trigger for Message Notifications
-- Triggers when a new message is inserted. Crucial detail: notifies ONLY the recipient user,
-- preventing notification spam/fatigue for the message sender.
CREATE OR REPLACE FUNCTION public.create_message_notifications()
RETURNS TRIGGER AS $$
DECLARE
    v_user1_id UUID;
    v_user2_id UUID;
    v_recipient_id UUID;
BEGIN
    -- Get match users
    SELECT user1_id, user2_id INTO v_user1_id, v_user2_id
    FROM public.matches
    WHERE id = NEW.match_id;

    -- Determine recipient user
    IF NEW.sender_id = v_user1_id THEN
        v_recipient_id := v_user2_id;
    ELSE
        v_recipient_id := v_user1_id;
    END IF;

    -- Create notification for the recipient only
    IF v_recipient_id IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, title, body)
        VALUES (v_recipient_id, 'لديك رسالة جديدة', 'لديك رسالة جديدة في غرفة التركيز');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER message_notification_trigger
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.create_message_notifications();
