-- Complete Fellowship Feature Setup
-- This migration ensures all necessary columns and functions exist for the Fellowship feature

-- 1. Add is_fellowship_only column to community_posts if it doesn't exist
ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS is_fellowship_only BOOLEAN DEFAULT false;

-- 2. Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_community_posts_fellowship 
ON community_posts(is_fellowship_only, user_id);

-- 3. Drop and recreate the get_fellowship_feed function with proper typing
DROP FUNCTION IF EXISTS get_fellowship_feed(UUID);

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

-- 4. Update existing posts that might be missing the is_fellowship_only flag
-- (This is a safety measure - won't affect posts that already have the correct value)
UPDATE community_posts 
SET is_fellowship_only = false 
WHERE is_fellowship_only IS NULL;

-- 5. Ensure RLS policies are set up correctly for fellowship posts
-- Create policy for reading fellowship posts (if it doesn't exist)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'community_posts' 
    AND policyname = 'Users can read fellowship posts'
  ) THEN
    CREATE POLICY "Users can read fellowship posts" ON community_posts
    FOR SELECT USING (
      -- Can read if:
      -- 1. It's not a fellowship-only post (public)
      -- 2. It's their own fellowship post
      -- 3. It's from someone in their fellowship
      is_fellowship_only = false 
      OR auth.uid() = user_id
      OR (
        is_fellowship_only = true 
        AND user_id IN (
          SELECT fellow_id FROM fellowships WHERE user_id = auth.uid()
        )
      )
    );
  END IF;
END $$;

-- 6. Ensure encouragements table exists and has proper structure
CREATE TABLE IF NOT EXISTS encouragements (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT,
  message TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for encouragements
CREATE INDEX IF NOT EXISTS idx_encouragements_post_id ON encouragements(post_id);
CREATE INDEX IF NOT EXISTS idx_encouragements_user_id ON encouragements(user_id);

-- 7. Ensure reactions table exists and has proper structure
CREATE TABLE IF NOT EXISTS reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction TEXT NOT NULL CHECK (reaction IN ('amen', 'pray', 'love', 'hallelujah', 'strength')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, user_id, reaction)
);

-- Create index for reactions
CREATE INDEX IF NOT EXISTS idx_reactions_post_id ON reactions(post_id);
CREATE INDEX IF NOT EXISTS idx_reactions_user_id ON reactions(user_id);

-- 8. Enable realtime for reactions and encouragements
-- Note: ALTER PUBLICATION doesn't support IF NOT EXISTS, so we need to check first
DO $$ 
BEGIN
  -- Check and add reactions table to realtime
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'reactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE reactions;
  END IF;
  
  -- Check and add encouragements table to realtime
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'encouragements'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE encouragements;
  END IF;
END $$;

-- 9. Grant necessary permissions
GRANT ALL ON encouragements TO authenticated;
GRANT ALL ON reactions TO authenticated;

-- Success message
SELECT 'Fellowship feature setup completed successfully!' as message;