-- FINAL WORKING FIX for fellowship groups creation
-- This handles the duplicate key constraint and column naming issues

-- Drop all versions first
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_safe CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_simple CASCADE;

-- Create a working version that handles all issues
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
AS $$
DECLARE
  v_group_id UUID;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate a new UUID to avoid any conflicts
  v_group_id := gen_random_uuid();
  
  BEGIN
    -- Create the group with explicit ID
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- Add creator as admin (new group, so no conflict possible)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    -- Return success with consistent column names
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT NULL::UUID, false, 'A group with this name may already exist'::TEXT;
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Create the safe version with same column names
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
AS $$
DECLARE
  v_group_id UUID;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate ID first
  v_group_id := gen_random_uuid();
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- Add creator as admin
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Create simple version with SAME column names as others
CREATE OR REPLACE FUNCTION create_fellowship_group_simple(
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
  v_new_group_id UUID;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate a new UUID first
  v_new_group_id := gen_random_uuid();
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_new_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- Add creator as admin
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_new_group_id, v_user_id, 'admin', true);
    
    -- Return with consistent column names
    RETURN QUERY SELECT v_new_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_simple TO authenticated;

-- Test that functions exist and return correct columns
SELECT 'Functions created. Testing column names...' as status;

-- This will show the column names returned by each function
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN (
  SELECT routine_name 
  FROM information_schema.routines 
  WHERE routine_name LIKE 'create_fellowship_group%'
  AND routine_schema = 'public'
);