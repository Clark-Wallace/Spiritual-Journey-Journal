-- Fix type mismatch in get_fellowship_feed function

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
    cp.user_id as user_id,
    cp.user_name::TEXT as user_name,  -- Cast VARCHAR to TEXT
    cp.content::TEXT as content,  -- Cast to TEXT
    cp.mood::TEXT as mood,  -- Cast to TEXT
    cp.gratitude,
    cp.prayer::TEXT as prayer,  -- Cast to TEXT
    cp.share_type::TEXT as share_type,  -- Cast to TEXT
    cp.is_anonymous,
    cp.is_fellowship_only,
    cp.group_id as group_id,
    fg.name::TEXT as group_name,  -- Cast to TEXT
    cp.created_at as created_at
  FROM community_posts cp
  LEFT JOIN fellowship_groups fg ON fg.id = cp.group_id
  WHERE 
    cp.is_fellowship_only = true
    AND (
      -- Posts from people in your fellowship (no group)
      (cp.group_id IS NULL AND (
        cp.user_id = for_user_id 
        OR cp.user_id IN (
          SELECT fellow_id FROM fellowships WHERE fellowships.user_id = for_user_id
        )
      ))
      OR
      -- Posts from groups you're a member of
      (cp.group_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM fellowship_group_members fgm
        WHERE fgm.group_id = cp.group_id
        AND fgm.user_id = for_user_id
        AND fgm.is_active = true
      ))
    )
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_fellowship_feed TO authenticated;

-- Also fix the get_group_posts function
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
    cp.user_name::TEXT as user_name,  -- Cast to TEXT
    cp.content::TEXT as content,  -- Cast to TEXT
    cp.mood::TEXT as mood,  -- Cast to TEXT
    cp.gratitude,
    cp.prayer::TEXT as prayer,  -- Cast to TEXT
    cp.share_type::TEXT as share_type,  -- Cast to TEXT
    cp.is_anonymous,
    cp.created_at
  FROM community_posts cp
  WHERE cp.group_id = p_group_id
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION get_group_posts TO authenticated;

-- Test the functions
SELECT 'Testing functions:' as status;
SELECT COUNT(*) as feed_count FROM get_fellowship_feed(auth.uid());

SELECT 'Functions fixed!' as status;