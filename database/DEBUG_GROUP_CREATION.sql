-- Debug script to find out what's really happening with group creation

-- 1. Check if there are any existing groups with these names
SELECT 'Existing groups:' as check_type;
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
WHERE name IN ('Mens Group', 'Mens Group 011', 'my group')
ORDER BY created_at DESC;

-- 2. Check all unique constraints on fellowship_groups table
SELECT 'Unique constraints on fellowship_groups:' as check_type;
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'fellowship_groups'::regclass
AND contype = 'u';

-- 3. Check all unique indexes on fellowship_groups
SELECT 'Unique indexes on fellowship_groups:' as check_type;
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'fellowship_groups'
AND indexdef LIKE '%UNIQUE%';

-- 4. Check if there's a unique constraint on the name column
SELECT 'Columns with unique constraints:' as check_type;
SELECT 
    a.attname as column_name,
    i.indisunique as is_unique
FROM pg_index i
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
WHERE i.indrelid = 'fellowship_groups'::regclass
AND i.indisunique = true;

-- 5. Test creating a group directly (bypassing the function)
-- First, let's see if we can insert directly
DO $$
DECLARE
    test_id UUID := gen_random_uuid();
    test_user_id UUID;
BEGIN
    -- Get a valid user ID (yours)
    test_user_id := 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;
    
    -- Try to insert a test group
    BEGIN
        INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
        VALUES (test_id, 'Test Group ' || extract(epoch from now())::text, 'Test', 'general', test_user_id, false);
        
        RAISE NOTICE 'SUCCESS: Test group created with ID %', test_id;
        
        -- Clean up the test
        DELETE FROM fellowship_groups WHERE id = test_id;
        RAISE NOTICE 'Test group deleted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'UNIQUE VIOLATION: %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'ERROR: %', SQLERRM;
    END;
END $$;

-- 6. Check what the actual error is in the function
-- Create a debug version that returns the actual error
CREATE OR REPLACE FUNCTION create_fellowship_group_debug(
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
AS $$
DECLARE
  v_group_id UUID;
  v_user_id UUID;
  v_error_detail TEXT;
  v_error_hint TEXT;
  v_error_context TEXT;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate a new UUID
  v_group_id := gen_random_uuid();
  
  -- Try to create the group and capture ALL error details
  BEGIN
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS 
        v_error_detail = PG_EXCEPTION_DETAIL,
        v_error_hint = PG_EXCEPTION_HINT,
        v_error_context = PG_EXCEPTION_CONTEXT;
      
      RETURN QUERY SELECT 
        NULL::UUID, 
        false, 
        format('UNIQUE VIOLATION - Message: %s, Detail: %s, Hint: %s', 
               SQLERRM, 
               COALESCE(v_error_detail, 'none'), 
               COALESCE(v_error_hint, 'none'))::TEXT;
               
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS 
        v_error_detail = PG_EXCEPTION_DETAIL,
        v_error_hint = PG_EXCEPTION_HINT,
        v_error_context = PG_EXCEPTION_CONTEXT;
        
      RETURN QUERY SELECT 
        NULL::UUID, 
        false, 
        format('ERROR - Message: %s, Detail: %s, Hint: %s', 
               SQLERRM, 
               COALESCE(v_error_detail, 'none'), 
               COALESCE(v_error_hint, 'none'))::TEXT;
  END;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION create_fellowship_group_debug TO authenticated;

-- Test the debug function
SELECT * FROM create_fellowship_group_debug('Debug Test Group', 'Testing', 'general', false);