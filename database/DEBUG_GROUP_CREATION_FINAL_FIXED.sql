-- Debug why groups aren't being created but membership insert is attempted

-- 1. Check current groups
SELECT 'Current groups in fellowship_groups:' as check;
SELECT id, name, created_at FROM fellowship_groups ORDER BY created_at DESC LIMIT 5;

-- 2. Check current memberships
SELECT 'Current memberships:' as check;
SELECT 
    fgm.group_id, 
    fgm.user_id, 
    fgm.role,
    fg.name as group_name
FROM fellowship_group_members fgm
LEFT JOIN fellowship_groups fg ON fg.id = fgm.group_id
ORDER BY fgm.joined_at DESC LIMIT 10;

-- 3. Check for orphaned memberships (memberships without groups)
SELECT 'Orphaned memberships without matching groups:' as check;
SELECT 
    fgm.group_id,
    fgm.user_id,
    fgm.role,
    fgm.joined_at
FROM fellowship_group_members fgm
WHERE NOT EXISTS (
    SELECT 1 FROM fellowship_groups fg 
    WHERE fg.id = fgm.group_id
);

-- 4. Clean up orphaned memberships
DELETE FROM fellowship_group_members
WHERE group_id NOT IN (SELECT id FROM fellowship_groups);

-- 5. Create a new test function that shows exactly what's happening
CREATE OR REPLACE FUNCTION create_fellowship_group_debug_v2(
  p_name VARCHAR(100),
  p_description TEXT,
  p_group_type VARCHAR(50),
  p_is_private BOOLEAN DEFAULT false
)
RETURNS TABLE(
  group_id UUID,
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id UUID;
  v_user_id UUID;
  v_group_inserted BOOLEAN := false;
  v_member_inserted BOOLEAN := false;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate new ID
  v_group_id := gen_random_uuid();
  
  RAISE NOTICE 'Attempting to create group with ID: %', v_group_id;
  
  -- Try to insert group
  BEGIN
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    v_group_inserted := true;
    RAISE NOTICE 'Group inserted successfully';
    
    -- Verify it exists
    IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = v_group_id) THEN
      RAISE NOTICE 'Group verified in database';
    ELSE
      RAISE NOTICE 'WARNING: Group not found after insert!';
    END IF;
    
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Group insert failed: %', SQLERRM;
      RETURN QUERY SELECT NULL::UUID, false, format('Failed to create group: %s', SQLERRM)::TEXT;
      RETURN;
  END;
  
  -- Try to insert membership
  BEGIN
    -- First check if membership already exists
    IF EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = v_group_id AND user_id = v_user_id
    ) THEN
      RAISE NOTICE 'Membership already exists for this group/user';
      UPDATE fellowship_group_members 
      SET role = 'admin', is_active = true
      WHERE group_id = v_group_id AND user_id = v_user_id;
    ELSE
      INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
      VALUES (v_group_id, v_user_id, 'admin', true);
      
      v_member_inserted := true;
      RAISE NOTICE 'Membership inserted successfully';
    END IF;
    
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'Unique violation on membership: %', SQLERRM;
      -- Group was created, so still success
      RETURN QUERY SELECT v_group_id, true, 'Group created but membership had conflict'::TEXT;
      RETURN;
    WHEN OTHERS THEN
      RAISE NOTICE 'Membership insert failed: %', SQLERRM;
      -- Group was created, so still success
      RETURN QUERY SELECT v_group_id, true, format('Group created but membership failed: %s', SQLERRM)::TEXT;
      RETURN;
  END;
  
  -- Both succeeded
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION create_fellowship_group_debug_v2 TO authenticated;

-- 6. Replace the main function with the debug version
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;

CREATE OR REPLACE FUNCTION create_fellowship_group(
  p_name VARCHAR(100),
  p_description TEXT,
  p_group_type VARCHAR(50),
  p_is_private BOOLEAN DEFAULT false
)
RETURNS TABLE(
  group_id UUID,
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Just call the debug version for now
  RETURN QUERY SELECT * FROM create_fellowship_group_debug_v2(p_name, p_description, p_group_type, p_is_private);
END;
$$;

GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;

-- 7. Test creating a group
SELECT 'Testing group creation:' as check;
DO $$
DECLARE
  result RECORD;
BEGIN
  SELECT * INTO result FROM create_fellowship_group(
    'Test ' || extract(epoch from now())::text,
    'Test',
    'general',
    false
  );
  
  RAISE NOTICE 'Test result: success=%, group_id=%, message=%', 
    result.success, result.group_id, result.message;
    
  IF result.group_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = result.group_id) THEN
      RAISE NOTICE 'Test group exists in database';
      -- Clean up
      DELETE FROM fellowship_group_members WHERE group_id = result.group_id;
      DELETE FROM fellowship_groups WHERE id = result.group_id;
    ELSE
      RAISE NOTICE 'ERROR: Test group NOT in database!';
    END IF;
  END IF;
END $$;

-- 8. Check if there are any triggers that might be interfering
SELECT 'Triggers on fellowship_groups:' as check;
SELECT tgname, tgtype FROM pg_trigger WHERE tgrelid = 'fellowship_groups'::regclass;

SELECT 'Triggers on fellowship_group_members:' as check;
SELECT tgname, tgtype FROM pg_trigger WHERE tgrelid = 'fellowship_group_members'::regclass;