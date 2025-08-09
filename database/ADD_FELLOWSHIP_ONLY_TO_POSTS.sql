-- Add is_fellowship_only column to community_posts table
-- This allows posts to be shared only with fellowship members

ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS is_fellowship_only BOOLEAN DEFAULT false;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_community_posts_fellowship 
ON community_posts(is_fellowship_only, user_id);

-- Drop existing function if it exists (needed to change return type)
DROP FUNCTION IF EXISTS get_fellowship_feed(UUID);

-- Create updated get_fellowship_feed RPC function to include fellowship-only posts
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
BEGIN
  -- Check if user has any fellowships
  IF NOT EXISTS (
    SELECT 1 FROM fellowships f WHERE f.user_id = for_user_id
  ) THEN
    -- Return only user's own fellowship posts if no fellowships
    RETURN QUERY
    SELECT 
      cp.id as post_id,
      cp.user_id,
      cp.user_name,
      cp.content,
      cp.mood,
      cp.gratitude,
      cp.prayer,
      cp.share_type,
      cp.is_anonymous,
      cp.is_fellowship_only,
      cp.created_at
    FROM community_posts cp
    WHERE cp.user_id = for_user_id
      AND cp.is_fellowship_only = true
    ORDER BY cp.created_at DESC;
  ELSE
    -- Return posts from user and their fellows (fellowship-only posts)
    RETURN QUERY
    SELECT 
      cp.id as post_id,
      cp.user_id,
      cp.user_name,
      cp.content,
      cp.mood,
      cp.gratitude,
      cp.prayer,
      cp.share_type,
      cp.is_anonymous,
      cp.is_fellowship_only,
      cp.created_at
    FROM community_posts cp
    WHERE cp.is_fellowship_only = true
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

-- Comment for documentation
COMMENT ON COLUMN community_posts.is_fellowship_only IS 'If true, post is only visible to fellowship members, not the general community';