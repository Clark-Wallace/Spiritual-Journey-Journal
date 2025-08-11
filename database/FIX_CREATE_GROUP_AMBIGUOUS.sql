-- Fix the ambiguous group_id reference in create_fellowship_group function

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
  
  -- Start a transaction block
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING fellowship_groups.id INTO v_group_id;
    
    -- Add creator as admin (using explicit table qualification)
    INSERT INTO fellowship_group_members AS fgm (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET 
      role = EXCLUDED.role,
      is_active = EXCLUDED.is_active;
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      -- If we still get a unique violation, handle it gracefully
      RETURN QUERY SELECT NULL::UUID, false, 'Error creating group - please try again'::TEXT;
    WHEN OTHERS THEN
      -- Handle any other errors with more detail
      RETURN QUERY SELECT NULL::UUID, false, format('Error creating group: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Alternative approach if the above still has issues
-- This version avoids ON CONFLICT entirely
DROP FUNCTION IF EXISTS create_fellowship_group_safe CASCADE;

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
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Create the group
  INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
  VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
  RETURNING fellowship_groups.id INTO v_group_id;
  
  -- Check if member already exists (shouldn't happen for new group, but be safe)
  SELECT EXISTS(
    SELECT 1 FROM fellowship_group_members 
    WHERE fellowship_group_members.group_id = v_group_id 
    AND fellowship_group_members.user_id = v_user_id
  ) INTO v_member_exists;
  
  IF NOT v_member_exists THEN
    -- Add creator as admin
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
  ELSE
    -- Update existing member to admin (shouldn't happen but be safe)
    UPDATE fellowship_group_members 
    SET role = 'admin', is_active = true
    WHERE fellowship_group_members.group_id = v_group_id 
    AND fellowship_group_members.user_id = v_user_id;
  END IF;
  
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Return detailed error message
    RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;