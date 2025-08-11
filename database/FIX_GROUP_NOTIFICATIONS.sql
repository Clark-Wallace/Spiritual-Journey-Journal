-- Create notification system for Fellowship Groups (Fixed)

-- 1. Create table to track last read timestamps for each group per user
CREATE TABLE IF NOT EXISTS fellowship_group_last_read (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id UUID NOT NULL REFERENCES fellowship_groups(id) ON DELETE CASCADE,
  last_read_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, group_id)
);

-- 2. Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_group_last_read_user_group 
ON fellowship_group_last_read(user_id, group_id);

-- 3. Enable RLS
ALTER TABLE fellowship_group_last_read ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies
DROP POLICY IF EXISTS "Users can view their own last read timestamps" ON fellowship_group_last_read;
CREATE POLICY "Users can view their own last read timestamps"
  ON fellowship_group_last_read FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own last read timestamps" ON fellowship_group_last_read;
CREATE POLICY "Users can update their own last read timestamps"
  ON fellowship_group_last_read FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can modify their own last read timestamps" ON fellowship_group_last_read;
CREATE POLICY "Users can modify their own last read timestamps"
  ON fellowship_group_last_read FOR UPDATE
  USING (user_id = auth.uid());

-- 5. Function to mark a group as read
CREATE OR REPLACE FUNCTION mark_group_as_read(p_group_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO fellowship_group_last_read (user_id, group_id, last_read_at)
  VALUES (auth.uid(), p_group_id, NOW())
  ON CONFLICT (user_id, group_id)
  DO UPDATE SET 
    last_read_at = NOW(),
    updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION mark_group_as_read TO authenticated;

-- 6. Function to get unread counts for all groups
CREATE OR REPLACE FUNCTION get_group_unread_counts()
RETURNS TABLE(
  group_id UUID,
  unread_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fgm.group_id,
    COUNT(cp.id)::BIGINT as unread_count
  FROM fellowship_group_members fgm
  LEFT JOIN fellowship_group_last_read lr 
    ON lr.group_id = fgm.group_id 
    AND lr.user_id = auth.uid()
  LEFT JOIN community_posts cp 
    ON cp.group_id = fgm.group_id
    AND cp.created_at > COALESCE(lr.last_read_at, '1970-01-01'::timestamptz)
    AND cp.user_id != auth.uid()  -- Don't count user's own posts
  WHERE 
    fgm.user_id = auth.uid()
    AND fgm.is_active = true
  GROUP BY fgm.group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_group_unread_counts TO authenticated;

-- 7. Function to get unread count for a specific group
CREATE OR REPLACE FUNCTION get_group_unread_count(p_group_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count BIGINT;
  v_last_read TIMESTAMPTZ;
BEGIN
  -- Check if user is a member
  IF NOT EXISTS (
    SELECT 1 FROM fellowship_group_members
    WHERE group_id = p_group_id
    AND user_id = auth.uid()
    AND is_active = true
  ) THEN
    RETURN 0;
  END IF;
  
  -- Get last read timestamp
  SELECT last_read_at INTO v_last_read
  FROM fellowship_group_last_read
  WHERE user_id = auth.uid()
  AND group_id = p_group_id;
  
  -- If never read, use epoch
  IF v_last_read IS NULL THEN
    v_last_read := '1970-01-01'::timestamptz;
  END IF;
  
  -- Count unread posts
  SELECT COUNT(*) INTO v_count
  FROM community_posts
  WHERE group_id = p_group_id
  AND created_at > v_last_read
  AND user_id != auth.uid();  -- Don't count user's own posts
  
  RETURN COALESCE(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_group_unread_count TO authenticated;

-- 8. Enable realtime for the tables
-- First check if table is already in publication
DO $$
BEGIN
  -- Add fellowship_group_last_read if not already in publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'fellowship_group_last_read'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_group_last_read;
  END IF;
  
  -- Add community_posts if not already in publication
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'community_posts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
  END IF;
END $$;

-- 9. Test the functions
SELECT 'Testing notification functions:' as status;

-- Get all unread counts
SELECT * FROM get_group_unread_counts();

SELECT 'Group notification system created!' as status;