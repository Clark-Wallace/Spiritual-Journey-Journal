-- Fix Fellowship Function Permission Issue
-- Run this in Supabase SQL Editor

-- Drop the old function that tries to access auth.users
DROP FUNCTION IF EXISTS get_fellowship_members(UUID);

-- Create a simpler version that doesn't need auth.users access
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    f.fellow_id,
    '' as fellow_name, -- We'll get names from community_posts or chat_messages instead
    f.created_at
  FROM fellowships f
  WHERE f.user_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;

-- Verify the function works
SELECT * FROM get_fellowship_members(auth.uid());