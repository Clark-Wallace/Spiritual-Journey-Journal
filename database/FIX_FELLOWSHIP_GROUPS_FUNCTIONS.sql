-- Safe migration to ensure all Fellowship Groups RPC functions exist
-- This script checks for existence before creating to avoid errors

-- 1. Drop and recreate the main create_fellowship_group function
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
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING fellowship_groups.id INTO v_group_id;
    
    -- Add creator as admin
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET 
      role = EXCLUDED.role,
      is_active = EXCLUDED.is_active;
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT NULL::UUID, false, 'A group with this name may already exist'::TEXT;
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Error creating group: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- 2. Create the safe version as backup
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
  
  BEGIN
    -- Create the group
    INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
    VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
    RETURNING fellowship_groups.id INTO v_group_id;
    
    -- Check if member already exists
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
      -- Update existing member to admin
      UPDATE fellowship_group_members 
      SET role = 'admin', is_active = true
      WHERE fellowship_group_members.group_id = v_group_id 
      AND fellowship_group_members.user_id = v_user_id;
    END IF;
    
    RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
    
  EXCEPTION
    WHEN OTHERS THEN
      RETURN QUERY SELECT NULL::UUID, false, format('Error: %s', SQLERRM)::TEXT;
  END;
END;
$$;

-- 3. Ensure invite function exists
DROP FUNCTION IF EXISTS invite_to_fellowship_group CASCADE;

CREATE OR REPLACE FUNCTION invite_to_fellowship_group(
  p_group_id UUID,
  p_user_ids UUID[],
  p_message TEXT DEFAULT NULL
)
RETURNS TABLE(
  invited_count INTEGER,
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_invited_count INTEGER := 0;
  v_user_to_invite UUID;
BEGIN
  v_user_id := auth.uid();
  
  -- Check if user is admin/moderator of the group
  IF NOT EXISTS (
    SELECT 1 FROM fellowship_group_members 
    WHERE group_id = p_group_id 
    AND user_id = v_user_id 
    AND role IN ('admin', 'moderator')
    AND is_active = true
  ) THEN
    RETURN QUERY SELECT 0, false, 'You do not have permission to invite to this group'::TEXT;
    RETURN;
  END IF;
  
  -- Send invites to each user
  FOREACH v_user_to_invite IN ARRAY p_user_ids
  LOOP
    -- Check if user is already a member
    IF NOT EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = p_group_id 
      AND user_id = v_user_to_invite
      AND is_active = true
    ) THEN
      -- Create or update invite
      INSERT INTO fellowship_group_invites (group_id, invited_user_id, invited_by, message)
      VALUES (p_group_id, v_user_to_invite, v_user_id, p_message)
      ON CONFLICT (group_id, invited_user_id) 
      DO UPDATE SET 
        invited_by = v_user_id,
        message = p_message,
        status = 'pending',
        created_at = NOW(),
        expires_at = NOW() + INTERVAL '7 days';
      
      v_invited_count := v_invited_count + 1;
    END IF;
  END LOOP;
  
  RETURN QUERY SELECT v_invited_count, true, format('Invited %s users to the group', v_invited_count)::TEXT;
END;
$$;

-- 4. Ensure respond to invite function exists
DROP FUNCTION IF EXISTS respond_to_group_invite CASCADE;

CREATE OR REPLACE FUNCTION respond_to_group_invite(
  p_invite_id UUID,
  p_response VARCHAR(20)
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_invite RECORD;
BEGIN
  v_user_id := auth.uid();
  
  -- Get invite details
  SELECT * INTO v_invite
  FROM fellowship_group_invites
  WHERE id = p_invite_id 
  AND invited_user_id = v_user_id
  AND status = 'pending'
  AND expires_at > NOW();
  
  IF v_invite IS NULL THEN
    RETURN QUERY SELECT false, 'Invite not found or expired'::TEXT;
    RETURN;
  END IF;
  
  -- Update invite status
  UPDATE fellowship_group_invites
  SET status = p_response, responded_at = NOW()
  WHERE id = p_invite_id;
  
  -- If accepted, add to group
  IF p_response = 'accepted' THEN
    INSERT INTO fellowship_group_members (group_id, user_id, role, invited_by)
    VALUES (v_invite.group_id, v_user_id, 'member', v_invite.invited_by)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET is_active = true, role = 'member';
    
    RETURN QUERY SELECT true, 'Successfully joined the group'::TEXT;
  ELSE
    RETURN QUERY SELECT true, 'Invite declined'::TEXT;
  END IF;
END;
$$;

-- 5. Ensure get my groups function exists
DROP FUNCTION IF EXISTS get_my_fellowship_groups CASCADE;

CREATE OR REPLACE FUNCTION get_my_fellowship_groups()
RETURNS TABLE(
  group_id UUID,
  group_name VARCHAR(100),
  description TEXT,
  group_type VARCHAR(50),
  member_count BIGINT,
  my_role VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fg.description,
    fg.group_type,
    COUNT(DISTINCT fgm2.user_id) as member_count,
    fgm.role as my_role,
    fg.created_at
  FROM fellowship_groups fg
  JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
  LEFT JOIN fellowship_group_members fgm2 ON fg.id = fgm2.group_id AND fgm2.is_active = true
  WHERE fgm.user_id = auth.uid() AND fgm.is_active = true
  GROUP BY fg.id, fg.name, fg.description, fg.group_type, fgm.role, fg.created_at
  ORDER BY fg.created_at DESC;
END;
$$;

-- 6. Grant execute permissions
GRANT EXECUTE ON FUNCTION create_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION create_fellowship_group_safe TO authenticated;
GRANT EXECUTE ON FUNCTION invite_to_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION respond_to_group_invite TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_fellowship_groups TO authenticated;

-- 7. Verify functions were created
SELECT 
    'Functions created:' as status,
    COUNT(*) as count
FROM pg_proc
WHERE proname IN (
    'create_fellowship_group',
    'create_fellowship_group_safe',
    'invite_to_fellowship_group',
    'respond_to_group_invite',
    'get_my_fellowship_groups'
)
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');