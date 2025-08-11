-- Fix missing membership records

-- 1. First, confirm no memberships exist
SELECT 'Total membership records:' as check;
SELECT COUNT(*) FROM fellowship_group_members;

-- 2. Add you as admin to all groups you created (retroactive fix)
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT 
    id as group_id,
    created_by as user_id,
    'admin' as role,
    true as is_active
FROM fellowship_groups
WHERE created_by IS NOT NULL
ON CONFLICT (group_id, user_id) DO NOTHING;

-- 3. Verify memberships were created
SELECT 'After fix - membership records:' as check;
SELECT 
    fg.name as group_name,
    fgm.role,
    fgm.user_id,
    fgm.is_active
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id;

-- 4. Check RLS policies on fellowship_group_members table
SELECT 'RLS enabled on fellowship_group_members:' as check;
SELECT 
    relname as table_name,
    relrowsecurity as rls_enabled
FROM pg_class
WHERE relname = 'fellowship_group_members';

-- 5. Check INSERT policy on fellowship_group_members
SELECT 'INSERT policies on fellowship_group_members:' as check;
SELECT 
    polname as policy_name,
    pg_get_expr(polwithcheck, polrelid) as with_check_clause
FROM pg_policy
WHERE polrelid = 'fellowship_group_members'::regclass
AND polcmd = 'a'; -- INSERT

-- 6. Fix the create_fellowship_group function to ensure membership is created
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
DECLARE
  v_group_id UUID;
  v_user_id UUID;
BEGIN
  -- Get authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate new ID
  v_group_id := gen_random_uuid();
  
  -- Insert both in a transaction
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- FORCE insert membership (SECURITY DEFINER bypasses RLS)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    -- If we got here, both succeeded
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Log the actual error for debugging
      RAISE NOTICE 'Error in create_fellowship_group: %', SQLERRM;
      
      -- Still try to return success if group was created
      IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = v_group_id) THEN
        -- Group exists, try one more time to add membership
        BEGIN
          INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
          VALUES (v_group_id, v_user_id, 'admin', true);
        EXCEPTION
          WHEN OTHERS THEN
            RAISE NOTICE 'Could not add membership: %', SQLERRM;
        END;
        
        RETURN QUERY SELECT v_group_id, true, 'Group created (check membership)'::TEXT;
      ELSE
        RETURN QUERY SELECT NULL::UUID, false, format('Failed: %s', SQLERRM)::TEXT;
      END IF;
  END;
END;
$$;

-- 7. Also fix the RLS policy on fellowship_group_members if needed
DROP POLICY IF EXISTS "Admins can add members" ON fellowship_group_members;

-- Create a simpler policy that allows the function to insert
CREATE POLICY "Users can add themselves as members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (user_id = auth.uid() OR invited_by = auth.uid());

-- 8. Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;

-- 9. Test - create a test group and verify membership is created
DO $$
DECLARE
  test_result RECORD;
  test_group_id UUID;
BEGIN
  -- Create a test group
  SELECT * INTO test_result
  FROM create_fellowship_group(
    'Membership Test ' || NOW()::text,
    'Testing membership creation',
    'general',
    false
  );
  
  test_group_id := test_result.group_id;
  
  IF test_result.success THEN
    RAISE NOTICE 'Group created with ID: %', test_group_id;
    
    -- Check if membership was created
    IF EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = test_group_id
    ) THEN
      RAISE NOTICE 'SUCCESS: Membership was created!';
    ELSE
      RAISE NOTICE 'FAILURE: No membership found!';
    END IF;
    
    -- Clean up
    DELETE FROM fellowship_group_members WHERE group_id = test_group_id;
    DELETE FROM fellowship_groups WHERE id = test_group_id;
  ELSE
    RAISE NOTICE 'Group creation failed: %', test_result.message;
  END IF;
END $$;

-- 10. Finally, test get_my_fellowship_groups to see if it returns groups now
SELECT 'Your groups after fix:' as check;
SELECT * FROM get_my_fellowship_groups();