-- Fellowship System Schema
-- Run this in your Supabase SQL editor

-- Create fellowship relationships table
CREATE TABLE IF NOT EXISTS fellowships (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fellow_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Prevent duplicate relationships
  UNIQUE(user_id, fellow_id),
  -- Prevent self-fellowship
  CHECK (user_id != fellow_id)
);

-- Create index for performance
CREATE INDEX idx_fellowships_user_id ON fellowships(user_id);
CREATE INDEX idx_fellowships_fellow_id ON fellowships(fellow_id);

-- Enable RLS
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;

-- Policies
-- Users can view their own fellowships
CREATE POLICY "Users can view own fellowships" ON fellowships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = fellow_id);

-- Users can add fellowships
CREATE POLICY "Users can add fellowships" ON fellowships
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can remove their own fellowships
CREATE POLICY "Users can remove own fellowships" ON fellowships
  FOR DELETE USING (auth.uid() = user_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE fellowships;

-- Function to check if two users are in fellowship
CREATE OR REPLACE FUNCTION is_in_fellowship(user1_id UUID, user2_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM fellowships 
    WHERE (user_id = user1_id AND fellow_id = user2_id)
       OR (user_id = user2_id AND fellow_id = user1_id)
  );
END;
$$ LANGUAGE plpgsql;

-- Function to get all fellowship members for a user
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    CASE 
      WHEN f.user_id = for_user_id THEN f.fellow_id
      ELSE f.user_id
    END as fellow_id,
    COALESCE(u.raw_user_meta_data->>'name', u.email) as fellow_name,
    f.created_at
  FROM fellowships f
  JOIN auth.users u ON u.id = CASE 
    WHEN f.user_id = for_user_id THEN f.fellow_id
    ELSE f.user_id
  END
  WHERE f.user_id = for_user_id OR f.fellow_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Add fellowship status to existing views/queries
-- This can be used to show fellowship indicators in chat
CREATE OR REPLACE VIEW chat_messages_with_fellowship AS
SELECT 
  cm.*,
  CASE 
    WHEN f.id IS NOT NULL THEN true 
    ELSE false 
  END as is_fellow
FROM chat_messages cm
LEFT JOIN fellowships f ON 
  (f.user_id = auth.uid() AND f.fellow_id = cm.user_id) OR
  (f.fellow_id = auth.uid() AND f.user_id = cm.user_id);

COMMENT ON TABLE fellowships IS 'Tracks fellowship relationships between users';
COMMENT ON FUNCTION is_in_fellowship IS 'Check if two users are in fellowship';
COMMENT ON FUNCTION get_fellowship_members IS 'Get all fellowship members for a user';