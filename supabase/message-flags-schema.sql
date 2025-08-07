-- Message Flags Schema for Chat Moderation
-- Run this in your Supabase SQL editor

-- Create table for tracking message flags
CREATE TABLE IF NOT EXISTS message_flags (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  flag_type TEXT NOT NULL CHECK (flag_type IN ('debate_room', 'not_the_way')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(message_id, user_id, flag_type)
);

-- Enable RLS
ALTER TABLE message_flags ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can flag messages" ON message_flags
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view flags" ON message_flags
  FOR SELECT USING (true);

CREATE POLICY "Users can remove their own flags" ON message_flags
  FOR DELETE USING (auth.uid() = user_id);

-- Create index for performance
CREATE INDEX idx_message_flags_message_id ON message_flags(message_id);
CREATE INDEX idx_message_flags_flag_type ON message_flags(flag_type);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE message_flags;

-- Function to get flag counts for a message
CREATE OR REPLACE FUNCTION get_message_flag_counts(msg_id UUID)
RETURNS TABLE(
  debate_room_count BIGINT,
  not_the_way_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(CASE WHEN flag_type = 'debate_room' THEN 1 END) as debate_room_count,
    COUNT(CASE WHEN flag_type = 'not_the_way' THEN 1 END) as not_the_way_count
  FROM message_flags
  WHERE message_id = msg_id;
END;
$$ LANGUAGE plpgsql;

-- Auto-hide messages with too many "Not The Way" flags (threshold: 3)
CREATE OR REPLACE FUNCTION check_message_flags()
RETURNS TRIGGER AS $$
DECLARE
  flag_count INTEGER;
BEGIN
  -- Count "not_the_way" flags for this message
  SELECT COUNT(*) INTO flag_count
  FROM message_flags
  WHERE message_id = NEW.message_id 
  AND flag_type = 'not_the_way';
  
  -- If 3 or more flags, mark message as hidden (you'll need to add a hidden column)
  IF flag_count >= 3 THEN
    UPDATE chat_messages 
    SET hidden = true 
    WHERE id = NEW.message_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add hidden column to chat_messages if not exists
ALTER TABLE chat_messages 
ADD COLUMN IF NOT EXISTS hidden BOOLEAN DEFAULT false;

-- Create trigger for auto-hiding
DROP TRIGGER IF EXISTS check_message_flags_trigger ON message_flags;
CREATE TRIGGER check_message_flags_trigger
  AFTER INSERT ON message_flags
  FOR EACH ROW
  EXECUTE FUNCTION check_message_flags();

-- Update RLS for chat_messages to filter hidden messages (optional)
-- This will hide flagged messages from everyone except the author
DROP POLICY IF EXISTS "Users can view non-hidden messages" ON chat_messages;
CREATE POLICY "Users can view non-hidden messages" ON chat_messages
  FOR SELECT USING (
    hidden = false OR user_id = auth.uid()
  );

COMMENT ON TABLE message_flags IS 'Tracks user flags on chat messages for moderation';
COMMENT ON COLUMN message_flags.flag_type IS 'debate_room: gentle redirect suggestion, not_the_way: inappropriate content flag';