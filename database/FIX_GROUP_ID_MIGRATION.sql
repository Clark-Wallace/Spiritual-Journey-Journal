-- Fix the group_id migration by dropping the function first

-- 1. Drop the existing function to allow changing return type
DROP FUNCTION IF EXISTS get_fellowship_feed(UUID);

-- 2. Add the group_id column if it doesn't exist
ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES fellowship_groups(id) ON DELETE CASCADE;

-- 3. Create an index for efficient group post queries
CREATE INDEX IF NOT EXISTS idx_community_posts_group_id 
ON community_posts(group_id) 
WHERE group_id IS NOT NULL;

-- 4. Update the RLS policy to allow members to see group posts
DROP POLICY IF EXISTS "Users can view fellowship group posts" ON community_posts;

CREATE POLICY "Users can view fellowship group posts"
  ON community_posts FOR SELECT
  USING (
    -- User can see the post if:
    -- 1. It's not a group post (group_id IS NULL)
    group_id IS NULL
    OR
    -- 2. User is a member of the group
    EXISTS (
      SELECT 1 FROM fellowship_group_members
      WHERE group_id = community_posts.group_id
      AND user_id = auth.uid()
      AND is_active = true
    )
  );

-- 5. Create the updated function with group support
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
  group_id UUID,
  group_name TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
    cp.group_id,
    fg.name as group_name,
    cp.created_at
  FROM community_posts cp
  LEFT JOIN fellowship_groups fg ON fg.id = cp.group_id
  WHERE 
    cp.is_fellowship_only = true
    AND (
      -- Posts from people in your fellowship (no group)
      (cp.group_id IS NULL AND (
        cp.user_id = for_user_id 
        OR cp.user_id IN (
          SELECT fellow_id FROM fellowships WHERE user_id = for_user_id
        )
      ))
      OR
      -- Posts from groups you're a member of
      (cp.group_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM fellowship_group_members
        WHERE group_id = cp.group_id
        AND user_id = for_user_id
        AND is_active = true
      ))
    )
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_fellowship_feed TO authenticated;

-- 6. Create a function to get posts for a specific group
DROP FUNCTION IF EXISTS get_group_posts(UUID);

CREATE OR REPLACE FUNCTION get_group_posts(p_group_id UUID)
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
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if user is a member of the group
  IF NOT EXISTS (
    SELECT 1 FROM fellowship_group_members
    WHERE group_id = p_group_id
    AND user_id = auth.uid()
    AND is_active = true
  ) THEN
    RAISE EXCEPTION 'You must be a member of this group to view its posts';
  END IF;
  
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
    cp.created_at
  FROM community_posts cp
  WHERE cp.group_id = p_group_id
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_group_posts TO authenticated;

-- 7. Test the new column
SELECT 'Testing group_id column:' as status;
SELECT COUNT(*) as posts_with_groups 
FROM community_posts 
WHERE group_id IS NOT NULL;

SELECT 'Group posts setup complete!' as status;