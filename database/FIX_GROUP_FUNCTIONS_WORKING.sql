-- WORKING FIX for fellowship groups functions
-- This version corrects the ON CONFLICT syntax error

-- Drop existing functions to recreate them properly
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_safe CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_simple CASCADE;

-- Create the main function with proper syntax
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
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING id INTO v_group_id;
    
    -- Add creator as admin (ON CONFLICT can't use table-qualified names)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET 
      role = EXCLUDED.role,
      is_active = EXCLUDED.is_active;
    
    -- Return with explicit naming
    RETURN QUERY SELECT v_group_id AS group_id, true AS success, 'Group created successfully'::TEXT AS message;
    
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, 'A group with this name may already exist'::TEXT AS message;
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, format('Error creating group: %s', SQLERRM)::TEXT AS message;
  END;
END;
$$;

-- Create the safe version without ON CONFLICT
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
  v_member_exists BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, 'User not authenticated'::TEXT AS message;
    RETURN;
  END IF;
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING id INTO v_group_id;
    
    -- Check if member already exists
    SELECT EXISTS(
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = v_group_id 
      AND fgm.user_id = v_user_id
    ) INTO v_member_exists;
    
    IF NOT v_member_exists THEN
      -- Add creator as admin
      INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
      VALUES (v_group_id, v_user_id, 'admin', true);
    ELSE
      -- Update existing member to admin
      UPDATE fellowship_group_members 
      SET role = 'admin', is_active = true
      WHERE group_id = v_group_id 
      AND user_id = v_user_id;
    END IF;
    
    -- Return with explicit naming
    RETURN QUERY SELECT v_group_id AS group_id, true AS success, 'Group created successfully'::TEXT AS message;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Return detailed error message
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, format('Error: %s', SQLERRM)::TEXT AS message;
  END;
END;
$$;

-- Simplest possible version - no conflicts possible
CREATE OR REPLACE FUNCTION create_fellowship_group_simple(
  p_name VARCHAR(100),
  p_description TEXT,
  p_group_type VARCHAR(50),
  p_is_private BOOLEAN DEFAULT false
)
RETURNS TABLE(
  out_group_id UUID,
  out_success BOOLEAN,
  out_message TEXT
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
    -- Create the group with explicit ID
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_new_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- Add creator as admin (no conflict possible with new group)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_new_group_id, v_user_id, 'admin', true);
    
    -- Return success
    RETURN QUERY SELECT v_new_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Return error
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_simple TO authenticated;

-- Verify functions were created
SELECT 
    proname as function_name,
    pg_get_function_identity_arguments(oid) as arguments
FROM pg_proc
WHERE proname LIKE 'create_fellowship_group%'
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;