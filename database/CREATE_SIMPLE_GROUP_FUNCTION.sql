-- Create the simplest possible group creation function

-- Drop the old broken function
DROP FUNCTION IF EXISTS create_fellowship_group CASCADE;

-- Create new SIMPLE version that just works
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
  -- Get user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, false, 'User not authenticated'::TEXT;
    RETURN;
  END IF;
  
  -- Generate new ID
  v_group_id := gen_random_uuid();
  
  -- Just insert the group - no fancy error handling
  INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
  VALUES (v_group_id, p_name, p_description, p_group_type, v_user_id, p_is_private);
  
  -- Add membership
  INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
  VALUES (v_group_id, v_user_id, 'admin', true);
  
  -- Return success
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Return the ACTUAL error, not a fake one
    RETURN QUERY SELECT NULL::UUID, false, SQLERRM::TEXT;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;

-- Test it
DO $$
DECLARE
  result RECORD;
BEGIN
  SELECT * INTO result
  FROM create_fellowship_group(
    'Test Group ' || extract(epoch from now())::text,
    'Testing simplified function',
    'general',
    false
  );
  
  RAISE NOTICE 'Result: success=%, message=%', result.success, result.message;
  
  IF result.success AND result.group_id IS NOT NULL THEN
    -- Clean up test
    DELETE FROM fellowship_group_members WHERE group_id = result.group_id;
    DELETE FROM fellowship_groups WHERE id = result.group_id;
    RAISE NOTICE 'Test group cleaned up';
  END IF;
END $$;

-- Check what groups exist now
SELECT 'Current groups:' as status;
SELECT id, name, created_at FROM fellowship_groups ORDER BY created_at DESC;