-- Fix for ambiguous column reference in get_fellowship_feed function
-- This version uses table aliases consistently to avoid ambiguity

-- First, ensure the is_fellowship_only column exists
ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS is_fellowship_only BOOLEAN DEFAULT false;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_community_posts_fellowship 
ON community_posts(is_fellowship_only, user_id);

-- Drop existing function
DROP FUNCTION IF EXISTS get_fellowship_feed(UUID);

-- Create fixed version with proper table aliases
CREATE OR REPLACE FUNCTION get_fellowship_feed(for_user_id UUID)
RETURNS TABLE(
  post_id UUID,
  user_id UUID,
  user_name TEXT,
  content TEXT,
  mood TEXT,
  gratitude TEXT[],
  prayer TEXT,
  share_type TEXT,
  is_anonymous BOOLEAN,
  is_fellowship_only BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  has_fellowships BOOLEAN;
BEGIN
  -- Check if user has any fellowships using table alias
  SELECT EXISTS(
    SELECT 1 FROM fellowships f WHERE f.user_id = for_user_id
  ) INTO has_fellowships;
  
  IF NOT has_fellowships THEN
    -- Return only user's own fellowship posts if no fellowships
    RETURN QUERY
    SELECT 
      cp.id::UUID as post_id,
      cp.user_id::UUID,
      cp.user_name::TEXT,
      cp.content::TEXT,
      cp.mood::TEXT,
      cp.gratitude::TEXT[],
      cp.prayer::TEXT,
      cp.share_type::TEXT,
      cp.is_anonymous::BOOLEAN,
      COALESCE(cp.is_fellowship_only, false)::BOOLEAN,
      cp.created_at::TIMESTAMP WITH TIME ZONE
    FROM community_posts cp
    WHERE cp.user_id = for_user_id
      AND COALESCE(cp.is_fellowship_only, false) = true
    ORDER BY cp.created_at DESC;
  ELSE
    -- Return posts from user and their fellows (fellowship-only posts)
    RETURN QUERY
    SELECT 
      cp.id::UUID as post_id,
      cp.user_id::UUID,
      cp.user_name::TEXT,
      cp.content::TEXT,
      cp.mood::TEXT,
      cp.gratitude::TEXT[],
      cp.prayer::TEXT,
      cp.share_type::TEXT,
      cp.is_anonymous::BOOLEAN,
      COALESCE(cp.is_fellowship_only, false)::BOOLEAN,
      cp.created_at::TIMESTAMP WITH TIME ZONE
    FROM community_posts cp
    WHERE COALESCE(cp.is_fellowship_only, false) = true
      AND (
        cp.user_id = for_user_id  -- User's own posts
        OR cp.user_id IN (         -- Fellows' posts
          SELECT f.fellow_id 
          FROM fellowships f
          WHERE f.user_id = for_user_id
        )
      )
    ORDER BY cp.created_at DESC;
  END IF;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_fellowship_feed(UUID) TO authenticated;

-- Add helpful comment
COMMENT ON FUNCTION get_fellowship_feed(UUID) IS 'Returns fellowship-only posts for a user and their fellows';