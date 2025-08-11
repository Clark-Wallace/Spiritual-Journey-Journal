-- Fix the get_my_fellowship_groups function and check why groups aren't showing

-- 1. First, check what groups exist for your user
SELECT 'Groups you created:' as check_type;
SELECT fg.id, fg.name, fg.created_by, fg.created_at
FROM fellowship_groups fg
WHERE fg.created_by = 'a43ff393-dde1-4001-b667-23f518e72499'
ORDER BY fg.created_at DESC;

-- 2. Check your memberships
SELECT 'Your group memberships:' as check_type;
SELECT 
    fg.id,
    fg.name,
    fgm.role,
    fgm.is_active,
    fgm.joined_at
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'
ORDER BY fgm.joined_at DESC;

-- 3. Check if the get_my_fellowship_groups function exists
SELECT 'Function exists:' as check_type;
SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'get_my_fellowship_groups'
);

-- 4. Drop and recreate the function with fixes
DROP FUNCTION IF EXISTS get_my_fellowship_groups CASCADE;

CREATE OR REPLACE FUNCTION get_my_fellowship_groups()
RETURNS TABLE(
  group_id UUID,
  group_name VARCHAR(100),
  description TEXT,
  group_type VARCHAR(50),
  member_count BIGINT,
  my_role VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fg.description,
    fg.group_type,
    COUNT(DISTINCT fgm2.user_id) as member_count,
    fgm.role as my_role,
    fg.created_at
  FROM fellowship_groups fg
  INNER JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
  LEFT JOIN fellowship_group_members fgm2 ON fg.id = fgm2.group_id AND fgm2.is_active = true
  WHERE fgm.user_id = auth.uid() 
    AND fgm.is_active = true
  GROUP BY fg.id, fg.name, fg.description, fg.group_type, fgm.role, fg.created_at
  ORDER BY fg.created_at DESC;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_my_fellowship_groups TO authenticated;

-- 5. Test the function
SELECT 'Testing get_my_fellowship_groups function:' as check_type;
SELECT * FROM get_my_fellowship_groups();

-- 6. Create a simpler version that doesn't rely on auth.uid() for debugging
CREATE OR REPLACE FUNCTION get_fellowship_groups_for_user(p_user_id UUID)
RETURNS TABLE(
  group_id UUID,
  group_name VARCHAR(100),
  description TEXT,
  group_type VARCHAR(50),
  member_count BIGINT,
  my_role VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fg.description,
    fg.group_type,
    COUNT(DISTINCT fgm2.user_id) as member_count,
    fgm.role as my_role,
    fg.created_at
  FROM fellowship_groups fg
  INNER JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
  LEFT JOIN fellowship_group_members fgm2 ON fg.id = fgm2.group_id AND fgm2.is_active = true
  WHERE fgm.user_id = p_user_id 
    AND fgm.is_active = true
  GROUP BY fg.id, fg.name, fg.description, fg.group_type, fgm.role, fg.created_at
  ORDER BY fg.created_at DESC;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_fellowship_groups_for_user TO authenticated;

-- 7. Test with your specific user ID
SELECT 'Testing with your user ID:' as check_type;
SELECT * FROM get_fellowship_groups_for_user('a43ff393-dde1-4001-b667-23f518e72499'::UUID);

-- 8. Check for any inactive memberships that might be causing issues
SELECT 'Inactive memberships:' as check_type;
SELECT 
    fg.name,
    fgm.role,
    fgm.is_active,
    fgm.joined_at
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'
  AND fgm.is_active = false;