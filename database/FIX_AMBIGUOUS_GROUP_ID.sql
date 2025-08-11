-- Fix ambiguous group_id column reference in RPC functions

-- Drop and recreate the invite_to_fellowship_group function with proper column references
DROP FUNCTION IF EXISTS invite_to_fellowship_group CASCADE;

CREATE OR REPLACE FUNCTION invite_to_fellowship_group(
  p_group_id UUID,
  p_user_ids UUID[],
  p_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_inviter_id UUID;
BEGIN
  v_inviter_id := auth.uid();
  
  -- Check if inviter is admin/moderator of the group
  IF NOT EXISTS (
    SELECT 1 FROM fellowship_group_members fgm
    WHERE fgm.group_id = p_group_id 
    AND fgm.user_id = v_inviter_id 
    AND fgm.role IN ('admin', 'moderator')
    AND fgm.is_active = true
  ) THEN
    RAISE EXCEPTION 'Only admins and moderators can invite members';
  END IF;
  
  -- Insert invites for each user
  FOREACH v_user_id IN ARRAY p_user_ids
  LOOP
    -- Check if user is in fellowship with inviter
    IF EXISTS (
      SELECT 1 FROM fellowships f
      WHERE (f.user_id = v_inviter_id AND f.fellow_id = v_user_id)
         OR (f.user_id = v_user_id AND f.fellow_id = v_inviter_id)
    ) THEN
      -- Create invite if not already member
      IF NOT EXISTS (
        SELECT 1 FROM fellowship_group_members fgm
        WHERE fgm.group_id = p_group_id 
        AND fgm.user_id = v_user_id
      ) THEN
        INSERT INTO fellowship_group_invites (
          group_id, 
          invited_user_id, 
          invited_by, 
          message,
          expires_at
        )
        VALUES (
          p_group_id, 
          v_user_id, 
          v_inviter_id, 
          p_message,
          NOW() + INTERVAL '7 days'
        )
        ON CONFLICT (group_id, invited_user_id) 
        WHERE status = 'pending'
        DO UPDATE SET 
          invited_by = v_inviter_id,
          message = p_message,
          expires_at = NOW() + INTERVAL '7 days',
          created_at = NOW();
      END IF;
    END IF;
  END LOOP;
  
  RETURN true;
END;
$$;

-- Also fix the get_my_fellowship_groups function to avoid ambiguity
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
    COALESCE(fgm.role, 'none')::VARCHAR(20) as my_role,
    fg.created_at
  FROM fellowship_groups fg
  LEFT JOIN fellowship_group_members fgm 
    ON fg.id = fgm.group_id 
    AND fgm.user_id = auth.uid() 
    AND fgm.is_active = true
  LEFT JOIN fellowship_group_members fgm2 
    ON fg.id = fgm2.group_id 
    AND fgm2.is_active = true
  WHERE 
    -- Include groups where user is a member
    fgm.user_id IS NOT NULL
    OR
    -- Include groups created by the user
    fg.created_by = auth.uid()
  GROUP BY fg.id, fg.name, fg.description, fg.group_type, fgm.role, fg.created_at
  ORDER BY fg.created_at DESC;
END;
$$;

-- Fix the respond_to_group_invite function as well
DROP FUNCTION IF EXISTS respond_to_group_invite CASCADE;

CREATE OR REPLACE FUNCTION respond_to_group_invite(
  p_invite_id UUID,
  p_response TEXT -- 'accepted' or 'declined'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_group_id UUID;
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  -- Get the group_id from the invite
  SELECT fgi.group_id INTO v_group_id
  FROM fellowship_group_invites fgi
  WHERE fgi.id = p_invite_id 
  AND fgi.invited_user_id = v_user_id 
  AND fgi.status = 'pending';
  
  IF v_group_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Update invite status
  UPDATE fellowship_group_invites
  SET status = p_response,
      responded_at = NOW()
  WHERE id = p_invite_id;
  
  -- If accepted, add user to group
  IF p_response = 'accepted' THEN
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'member', true)
    ON CONFLICT (group_id, user_id) 
    DO UPDATE SET is_active = true;
  END IF;
  
  RETURN true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION invite_to_fellowship_group TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_fellowship_groups TO authenticated;
GRANT EXECUTE ON FUNCTION respond_to_group_invite TO authenticated;