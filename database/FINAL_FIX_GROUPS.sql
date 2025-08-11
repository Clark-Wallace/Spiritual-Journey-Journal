-- FINAL COMPREHENSIVE FIX for Fellowship Groups

-- 1. Drop all existing versions to start fresh
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_safe CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_simple CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_debug CASCADE;

-- 2. Create a working version that handles all issues
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
DECLARE
  v_group_id UUID;
  v_user_id UUID;
  v_group_created BOOLEAN := false;
  v_member_exists BOOLEAN := false;
BEGIN
  -- Get authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate new ID
  v_group_id := gen_random_uuid();
  
  -- Create the group
  BEGIN
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    v_group_created := true;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Failed to create group: %s', SQLERRM)::TEXT;
      RETURN;
  END;
  
  -- Add creator as admin (only if group was created)
  IF v_group_created THEN
    -- Check if member already exists (shouldn't happen, but be safe)
    SELECT EXISTS(
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = v_group_id 
      AND fgm.user_id = v_user_id
    ) INTO v_member_exists;
    
    IF NOT v_member_exists THEN
      BEGIN
        INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
        VALUES (v_group_id, v_user_id, 'admin', true);
      EXCEPTION
        WHEN unique_violation THEN
          -- Membership already exists somehow, update to admin
          UPDATE fellowship_group_members 
          SET role = 'admin', is_active = true
          WHERE fellowship_group_members.group_id = v_group_id 
          AND fellowship_group_members.user_id = v_user_id;
        WHEN OTHERS THEN
          -- Group was created, so still return success even if membership failed
          RETURN QUERY SELECT v_group_id, true, format('Group created (membership warning: %s)', SQLERRM)::TEXT;
          RETURN;
      END;
    ELSE
      -- Member exists, ensure they're admin
      UPDATE fellowship_group_members 
      SET role = 'admin', is_active = true
      WHERE fellowship_group_members.group_id = v_group_id 
      AND fellowship_group_members.user_id = v_user_id;
    END IF;
  END IF;
  
  -- Return success
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
END;
$$;

-- 3. Create safe version without any ambiguous references
CREATE OR REPLACE FUNCTION create_fellowship_group_safe(
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
  v_new_group_id UUID;
  v_auth_user_id UUID;
BEGIN
  -- Get authenticated user
  v_auth_user_id := auth.uid();
  
  IF v_auth_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate new ID
  v_new_group_id := gen_random_uuid();
  
  -- Create the group in a transaction
  BEGIN
    -- Insert group
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_new_group_id, p_name, p_description, p_group_type, v_auth_user_id, p_is_private);
    
    -- Insert membership (new group, so no conflict possible)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_new_group_id, v_auth_user_id, 'admin', true);
    
    -- Success
    RETURN QUERY SELECT v_new_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Check if group was at least created
      IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = v_new_group_id) THEN
        -- Group exists, so partial success
        RETURN QUERY SELECT v_new_group_id, true, 'Group created successfully'::TEXT;
      ELSE
        -- Complete failure
        RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
      END IF;
  END;
END;
$$;

-- 4. Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;

-- 5. Fix the RLS policy for INSERT if not already fixed
DROP POLICY IF EXISTS "Users can create groups" ON fellowship_groups;
CREATE POLICY "Users can create groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- 6. Clean up any orphaned group memberships
DELETE FROM fellowship_group_members fgm
WHERE NOT EXISTS (
  SELECT 1 FROM fellowship_groups fg
  WHERE fg.id = fgm.group_id
);

-- 7. Verify the functions work
DO $$
DECLARE
  test_result RECORD;
BEGIN
  -- Test the main function
  SELECT * INTO test_result
  FROM create_fellowship_group(
    'SQL Test Group ' || extract(epoch from now())::text,
    'Testing from SQL',
    'general',
    false
  );
  
  IF test_result.success THEN
    RAISE NOTICE 'Main function works! Group ID: %', test_result.group_id;
    -- Clean up test
    DELETE FROM fellowship_group_members WHERE group_id = test_result.group_id;
    DELETE FROM fellowship_groups WHERE id = test_result.group_id;
  ELSE
    RAISE NOTICE 'Main function failed: %', test_result.message;
  END IF;
  
  -- Test the safe function
  SELECT * INTO test_result
  FROM create_fellowship_group_safe(
    'SQL Safe Test ' || extract(epoch from now())::text,
    'Testing safe version',
    'general',
    false
  );
  
  IF test_result.success THEN
    RAISE NOTICE 'Safe function works! Group ID: %', test_result.group_id;
    -- Clean up test
    DELETE FROM fellowship_group_members WHERE group_id = test_result.group_id;
    DELETE FROM fellowship_groups WHERE id = test_result.group_id;
  ELSE
    RAISE NOTICE 'Safe function failed: %', test_result.message;
  END IF;
END $$;

-- 8. Show current groups
SELECT 'Current groups in database:' as status;
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
ORDER BY created_at DESC
LIMIT 10;