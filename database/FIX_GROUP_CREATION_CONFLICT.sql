-- Fix duplicate key error when creating groups

-- Drop the old function and recreate with better error handling
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
    RETURNING id INTO v_group_id;
    
    -- Add creator as admin (with ON CONFLICT to handle duplicates)
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET 
      role = 'admin',
      is_active = true;
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      -- If we still get a unique violation, handle it gracefully
      RETURN QUERY SELECT NULL::UUID, false, 'Error creating group - please try again'::TEXT;
    WHEN OTHERS THEN
      -- Handle any other errors
      RETURN QUERY SELECT NULL::UUID, false, format('Error creating group: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- Also fix the trigger to use ON CONFLICT
DROP FUNCTION IF EXISTS ensure_creator_is_admin CASCADE;

CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER AS $$
BEGIN
  -- Add creator as admin member with ON CONFLICT handling
  INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
  VALUES (NEW.id, NEW.created_by, 'admin', true)
  ON CONFLICT (group_id, user_id) 
  DO UPDATE SET 
    role = 'admin',
    is_active = true;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
DROP TRIGGER IF EXISTS add_creator_as_admin ON fellowship_groups;
CREATE TRIGGER add_creator_as_admin
  AFTER INSERT ON fellowship_groups
  FOR EACH ROW
  EXECUTE FUNCTION ensure_creator_is_admin();

-- Clean up any duplicate entries that might exist
-- This will keep only the admin role if there are duplicates
DELETE FROM fellowship_group_members a
USING fellowship_group_members b
WHERE a.id < b.id 
  AND a.group_id = b.group_id 
  AND a.user_id = b.user_id;

-- Ensure all group creators are admins
UPDATE fellowship_group_members fgm
SET role = 'admin'
FROM fellowship_groups fg
WHERE fgm.group_id = fg.id 
  AND fgm.user_id = fg.created_by 
  AND fgm.role != 'admin';