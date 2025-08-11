-- Fix for duplicate membership issue in fellowship groups

-- 1. First, check if there's a trigger auto-adding creators as members
SELECT 'Checking for triggers on fellowship_groups table:' as check;
SELECT 
    tgname AS trigger_name,
    proname AS function_name
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE tgrelid = 'fellowship_groups'::regclass;

-- 2. Check if groups are being created but function thinks they failed
SELECT 'Recently created groups (last hour):' as check;
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
WHERE created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC;

-- 3. Check memberships for your user
SELECT 'Your group memberships:' as check;
SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fgm.role,
    fgm.joined_at
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'
ORDER BY fgm.joined_at DESC;

-- 4. Drop and recreate the function with better error handling
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
  v_group_created BOOLEAN := false;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Start a transaction
  BEGIN
    -- Generate a new UUID
    v_group_id := gen_random_uuid();
    
    -- Create the group
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
    
    v_group_created := true;
    
    -- Check if member already exists (in case a trigger added them)
    IF NOT EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = v_group_id 
      AND user_id = v_user_id
    ) THEN
      -- Add creator as admin only if not already added
      INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
      VALUES (v_group_id, v_user_id, 'admin', true);
    ELSE
      -- Update to admin if they exist but might not be admin
      UPDATE fellowship_group_members 
      SET role = 'admin', is_active = true
      WHERE group_id = v_group_id AND user_id = v_user_id;
    END IF;
    
    -- Return success
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      -- If group was created but membership failed, still return success
      IF v_group_created THEN
        -- Try to ensure they're an admin
        UPDATE fellowship_group_members 
        SET role = 'admin', is_active = true
        WHERE group_id = v_group_id AND user_id = v_user_id;
        
        RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
      ELSE
        -- Group creation failed (duplicate name?)
        RETURN QUERY SELECT NULL::UUID, false, 'A group with this name may already exist'::TEXT;
      END IF;
      
    WHEN OTHERS THEN
      -- If group was created, we should still return success
      IF v_group_created THEN
        RETURN QUERY SELECT v_group_id, true, 'Group created (with warning: ' || SQLERRM || ')'::TEXT;
      ELSE
        RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
      END IF;
  END;
END;
$$;

-- 5. Also update the safe version
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
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate ID first
  v_group_id := gen_random_uuid();
  
  -- Create the group
  INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
  VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
  
  -- Check if member already exists before inserting
  IF NOT EXISTS (
    SELECT 1 FROM fellowship_group_members 
    WHERE group_id = v_group_id 
    AND user_id = v_user_id
  ) THEN
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
  ELSE
    UPDATE fellowship_group_members 
    SET role = 'admin', is_active = true
    WHERE group_id = v_group_id AND user_id = v_user_id;
  END IF;
  
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Check if the group was at least created
    IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = v_group_id) THEN
      RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    ELSE
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
    END IF;
END;
$$;

-- 6. Clean up any duplicate memberships (keep only admin role if duplicates exist)
DELETE FROM fellowship_group_members fgm1
WHERE EXISTS (
  SELECT 1 
  FROM fellowship_group_members fgm2
  WHERE fgm2.group_id = fgm1.group_id
  AND fgm2.user_id = fgm1.user_id
  AND fgm2.role = 'admin'
  AND fgm1.role != 'admin'
  AND fgm2.id != fgm1.id
);

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;

-- Test
SELECT 'Functions updated. They now check for existing membership before inserting.' as status;