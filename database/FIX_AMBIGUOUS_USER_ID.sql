-- Fix ambiguous user_id reference in get_fellowship_feed function

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
    cp.user_id as user_id,  -- Explicitly alias to avoid ambiguity
    cp.user_name,
    cp.content,
    cp.mood,
    cp.gratitude,
    cp.prayer,
    cp.share_type,
    cp.is_anonymous,
    cp.is_fellowship_only,
    cp.group_id as group_id,  -- Explicitly alias to avoid ambiguity
    fg.name as group_name,
    cp.created_at as created_at  -- Explicitly alias to avoid ambiguity
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

-- Test the function
SELECT 'Testing get_fellowship_feed function:' as status;
SELECT COUNT(*) as feed_count FROM get_fellowship_feed(auth.uid());

SELECT 'Function fixed!' as status;