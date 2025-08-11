-- FINAL FIX for ambiguous group_id column reference in fellowship groups
-- Run this to fix the "column reference 'group_id' is ambiguous" error

-- Drop existing functions to recreate them properly
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;
DROP FUNCTION IF EXISTS create_fellowship_group_safe CASCADE;

-- Create the main function with proper column qualification
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
    -- Create the group with explicit table reference
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING fellowship_groups.id INTO v_group_id;
    
    -- Add creator as admin with explicit table reference
    INSERT INTO fellowship_group_members (fellowship_group_members.group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true)
    ON CONFLICT (fellowship_group_members.group_id, user_id) 
    DO UPDATE SET 
      role = EXCLUDED.role,
      is_active = EXCLUDED.is_active;
    
    -- Return with explicit naming to avoid ambiguity
    RETURN QUERY SELECT v_group_id AS group_id, true AS success, 'Group created successfully'::TEXT AS message;
    
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, 'A group with this name may already exist'::TEXT AS message;
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, format('Error creating group: %s', SQLERRM)::TEXT AS message;
  END;
END;
$$;

-- Create the safe version with proper column qualification
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
    RETURNING fellowship_groups.id INTO v_group_id;
    
    -- Check if member already exists with proper table qualification
    SELECT EXISTS(
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = v_group_id 
      AND fgm.user_id = v_user_id
    ) INTO v_member_exists;
    
    IF NOT v_member_exists THEN
      -- Add creator as admin without using column names that could be ambiguous
      INSERT INTO fellowship_group_members (fellowship_group_members.group_id, user_id, role, is_active)
      VALUES (v_group_id, v_user_id, 'admin', true);
    ELSE
      -- Update existing member to admin
      UPDATE fellowship_group_members fgm
      SET role = 'admin', is_active = true
      WHERE fgm.group_id = v_group_id 
      AND fgm.user_id = v_user_id;
    END IF;
    
    -- Return with explicit naming
    RETURN QUERY SELECT v_group_id AS group_id, true AS success, 'Group created successfully'::TEXT AS message;
    
  EXCEPTION
    WHEN OTHERS THEN
      -- Return detailed error message with explicit naming
      RETURN QUERY SELECT NULL::UUID AS group_id, false AS success, format('Error: %s', SQLERRM)::TEXT AS message;
  END;
END;
$$;

-- Alternative simplified version that avoids all potential conflicts
DROP FUNCTION IF EXISTS create_fellowship_group_simple CASCADE;

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
  
  -- Generate a new UUID first to avoid any conflicts
  v_new_group_id := gen_random_uuid();
  
  BEGIN
    -- Create the group with explicit ID
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_new_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    -- Add creator as admin
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

-- Test which version works (for debugging)
SELECT 'Functions created successfully. Test with: SELECT * FROM create_fellowship_group(''Test Group'', ''Test Description'', ''general'', false);' as instructions;