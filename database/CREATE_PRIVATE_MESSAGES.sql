-- Create Private Messaging System
-- This migration sets up direct messaging between users

-- 1. Create private_messages table
CREATE TABLE IF NOT EXISTS private_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_private_messages_from_user ON private_messages(from_user_id);
CREATE INDEX IF NOT EXISTS idx_private_messages_to_user ON private_messages(to_user_id);
CREATE INDEX IF NOT EXISTS idx_private_messages_created_at ON private_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_private_messages_conversation ON private_messages(
  LEAST(from_user_id, to_user_id), 
  GREATEST(from_user_id, to_user_id),
  created_at DESC
);

-- 3. Enable RLS
ALTER TABLE private_messages ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies
-- Users can see messages they sent or received
CREATE POLICY "Users can view their own messages" ON private_messages
FOR SELECT USING (
  auth.uid() = from_user_id OR auth.uid() = to_user_id
);

-- Users can send messages
CREATE POLICY "Users can send messages" ON private_messages
FOR INSERT WITH CHECK (
  auth.uid() = from_user_id
);

-- Users can update their own messages (for read status)
CREATE POLICY "Users can update read status" ON private_messages
FOR UPDATE USING (
  auth.uid() = to_user_id
) WITH CHECK (
  auth.uid() = to_user_id
);

-- Users can delete their own sent messages
CREATE POLICY "Users can delete their sent messages" ON private_messages
FOR DELETE USING (
  auth.uid() = from_user_id
);

-- 5. Create function to get conversations list
CREATE OR REPLACE FUNCTION get_user_conversations(p_user_id UUID)
RETURNS TABLE(
  conversation_with UUID,
  conversation_with_name TEXT,
  last_message TEXT,
  last_message_time TIMESTAMP WITH TIME ZONE,
  unread_count BIGINT,
  is_online BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH conversations AS (
    SELECT 
      CASE 
        WHEN from_user_id = p_user_id THEN to_user_id
        ELSE from_user_id
      END as other_user_id,
      message,
      created_at,
      is_read,
      CASE 
        WHEN to_user_id = p_user_id THEN NOT is_read
        ELSE false
      END as is_unread
    FROM private_messages
    WHERE from_user_id = p_user_id OR to_user_id = p_user_id
  ),
  latest_messages AS (
    SELECT DISTINCT ON (other_user_id)
      other_user_id,
      message,
      created_at,
      is_unread
    FROM conversations
    ORDER BY other_user_id, created_at DESC
  ),
  unread_counts AS (
    SELECT 
      other_user_id,
      COUNT(*) FILTER (WHERE is_unread) as unread_count
    FROM conversations
    GROUP BY other_user_id
  )
  SELECT 
    lm.other_user_id as conversation_with,
    COALESCE(up.display_name, 'Unknown User') as conversation_with_name,
    lm.message as last_message,
    lm.created_at as last_message_time,
    COALESCE(uc.unread_count, 0) as unread_count,
    CASE 
      WHEN upr.last_seen > NOW() - INTERVAL '5 minutes' THEN true
      ELSE false
    END as is_online
  FROM latest_messages lm
  LEFT JOIN user_profiles up ON up.user_id = lm.other_user_id
  LEFT JOIN unread_counts uc ON uc.other_user_id = lm.other_user_id
  LEFT JOIN user_presence upr ON upr.user_id = lm.other_user_id
  ORDER BY lm.created_at DESC;
END;
$$;

-- 6. Create function to get conversation messages
CREATE OR REPLACE FUNCTION get_conversation_messages(
  p_user_id UUID,
  p_other_user_id UUID,
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS TABLE(
  message_id UUID,
  from_user_id UUID,
  from_user_name TEXT,
  to_user_id UUID,
  to_user_name TEXT,
  message TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  is_mine BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Mark messages as read
  UPDATE private_messages
  SET is_read = true
  WHERE to_user_id = p_user_id 
    AND from_user_id = p_other_user_id
    AND is_read = false;
  
  -- Return messages
  RETURN QUERY
  SELECT 
    pm.id as message_id,
    pm.from_user_id,
    COALESCE(up_from.display_name, 'Unknown') as from_user_name,
    pm.to_user_id,
    COALESCE(up_to.display_name, 'Unknown') as to_user_name,
    pm.message,
    pm.is_read,
    pm.created_at,
    (pm.from_user_id = p_user_id) as is_mine
  FROM private_messages pm
  LEFT JOIN user_profiles up_from ON up_from.user_id = pm.from_user_id
  LEFT JOIN user_profiles up_to ON up_to.user_id = pm.to_user_id
  WHERE (
    (pm.from_user_id = p_user_id AND pm.to_user_id = p_other_user_id) OR
    (pm.from_user_id = p_other_user_id AND pm.to_user_id = p_user_id)
  )
  ORDER BY pm.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- 7. Grant permissions
GRANT EXECUTE ON FUNCTION get_user_conversations(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_conversation_messages(UUID, UUID, INT, INT) TO authenticated;
GRANT ALL ON private_messages TO authenticated;

-- 8. Enable realtime for private messages
DO $$ 
BEGIN
  -- Check and add private_messages table to realtime
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'private_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_messages;
  END IF;
END $$;

-- Success message
SELECT 'Private messaging system created successfully!' as message;