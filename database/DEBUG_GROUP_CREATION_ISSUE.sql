-- Debug why group creation is failing with unique violation

-- 1. Check if "Another Group" exists
SELECT 'Groups named "Another Group":' as check;
SELECT * FROM fellowship_groups WHERE name = 'Another Group';

-- 2. Check ALL unique constraints on fellowship_groups
SELECT 'All constraints on fellowship_groups:' as check;
SELECT 
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'fellowship_groups'::regclass;

-- 3. Check if there's a unique index on the name column
SELECT 'Indexes on fellowship_groups:' as check;
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'fellowship_groups';

-- 4. Try to create a group directly to see the real error
DO $$
DECLARE
    v_group_id UUID := gen_random_uuid();
    v_user_id UUID := 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;
BEGIN
    -- Try to insert
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, 'Direct Test Group ' || NOW()::text, 'Testing', 'general', v_user_id, false);
    
    RAISE NOTICE 'Group created successfully with ID: %', v_group_id;
    
    -- Try to add membership
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    RAISE NOTICE 'Membership added successfully';
    
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'UNIQUE VIOLATION: %', SQLERRM;
        RAISE NOTICE 'DETAIL: %', SQLSTATE;
    WHEN OTHERS THEN
        RAISE NOTICE 'OTHER ERROR: %', SQLERRM;
        RAISE NOTICE 'SQLSTATE: %', SQLSTATE;
END $$;

-- 5. Check what version of the function is currently running
SELECT 'Current create_fellowship_group function:' as check;
SELECT 
    proname,
    prosrc
FROM pg_proc
WHERE proname = 'create_fellowship_group'
LIMIT 1;

-- 6. Let's create a SUPER SIMPLE version that just logs everything
CREATE OR REPLACE FUNCTION create_fellowship_group_test(
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
  v_error_detail TEXT;
  v_error_state TEXT;
BEGIN
  v_user_id := auth.uid();
  v_group_id := gen_random_uuid();
  
  RAISE NOTICE 'Starting group creation - User: %, Group ID: %', v_user_id, v_group_id;
  
  -- Try to create group
  BEGIN
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    RAISE NOTICE 'Group inserted successfully';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS 
        v_error_detail = PG_EXCEPTION_DETAIL,
        v_error_state = RETURNED_SQLSTATE;
      
      RAISE NOTICE 'Group insert failed - Error: %, State: %, Detail: %', SQLERRM, v_error_state, v_error_detail;
      
      -- Return the ACTUAL error, not a generic message
      RETURN QUERY SELECT NULL::UUID, false, format('Group Error - %s (State: %s)', SQLERRM, v_error_state)::TEXT;
      RETURN;
  END;
  
  -- Try to create membership
  BEGIN
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    RAISE NOTICE 'Membership inserted successfully';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS 
        v_error_detail = PG_EXCEPTION_DETAIL,
        v_error_state = RETURNED_SQLSTATE;
      
      RAISE NOTICE 'Membership insert failed - Error: %, State: %, Detail: %', SQLERRM, v_error_state, v_error_detail;
      
      -- Group was created, so return success anyway
      RETURN QUERY SELECT v_group_id, true, format('Group created but membership failed: %s', SQLERRM)::TEXT;
      RETURN;
  END;
  
  -- Both succeeded
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION create_fellowship_group_test TO authenticated;

-- 7. Test the new function
SELECT 'Testing new test function:' as check;
SELECT * FROM create_fellowship_group_test('Test Function Group', 'Testing', 'general', false);