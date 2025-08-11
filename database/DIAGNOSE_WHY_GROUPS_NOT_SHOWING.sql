-- Diagnose why groups aren't showing even though memberships exist

-- 1. Verify memberships exist for your user
SELECT 'Your membership records:' as check;
SELECT 
    fgm.group_id,
    fgm.user_id,
    fgm.role,
    fgm.is_active,
    fg.name as group_name
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499';

-- 2. Test if auth.uid() is working in functions
SELECT 'Testing auth.uid():' as check;
SELECT auth.uid() as current_auth_uid;

-- 3. Test the get_my_fellowship_groups function directly
SELECT 'get_my_fellowship_groups() result:' as check;
SELECT * FROM get_my_fellowship_groups();

-- 4. Create a debug version that shows what's happening
CREATE OR REPLACE FUNCTION debug_my_groups()
RETURNS TABLE(
  debug_info TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_group_count INTEGER;
  v_membership_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  
  RETURN QUERY SELECT format('auth.uid() returns: %s', v_user_id::TEXT);
  
  SELECT COUNT(*) INTO v_group_count FROM fellowship_groups;
  RETURN QUERY SELECT format('Total groups in database: %s', v_group_count::TEXT);
  
  SELECT COUNT(*) INTO v_membership_count 
  FROM fellowship_group_members 
  WHERE user_id = v_user_id AND is_active = true;
  
  RETURN QUERY SELECT format('Active memberships for user: %s', v_membership_count::TEXT);
  
  -- Try the actual query
  SELECT COUNT(*) INTO v_group_count
  FROM fellowship_groups fg
  INNER JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
  WHERE fgm.user_id = v_user_id AND fgm.is_active = true;
  
  RETURN QUERY SELECT format('Groups found by join query: %s', v_group_count::TEXT);
END;
$$;

GRANT EXECUTE ON FUNCTION debug_my_groups TO authenticated;

-- 5. Run the debug function
SELECT 'Debug info:' as check;
SELECT * FROM debug_my_groups();

-- 6. Try a simpler version of get_my_fellowship_groups
CREATE OR REPLACE FUNCTION get_my_fellowship_groups_simple()
RETURNS TABLE(
  group_id UUID,
  group_name VARCHAR(100)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fg.id as group_id,
    fg.name as group_name
  FROM fellowship_groups fg
  JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
  WHERE fgm.user_id = auth.uid() 
    AND fgm.is_active = true;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_fellowship_groups_simple TO authenticated;

-- 7. Test the simple version
SELECT 'Simple function result:' as check;
SELECT * FROM get_my_fellowship_groups_simple();

-- 8. Check if it's an RLS issue on SELECT
SELECT 'Can you see fellowship_group_members records:' as check;
SELECT COUNT(*) as visible_memberships
FROM fellowship_group_members
WHERE user_id = 'a43ff393-dde1-4001-b667-23f518e72499';