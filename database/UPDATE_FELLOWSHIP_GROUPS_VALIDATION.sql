-- Update Fellowship Groups to enforce fellowship membership requirements

-- Function to validate that users are in fellowship before joining groups
CREATE OR REPLACE FUNCTION validate_fellowship_for_group()
RETURNS TRIGGER AS $$
DECLARE
  v_group_creator UUID;
  v_is_in_fellowship BOOLEAN;
BEGIN
  -- Get the group creator
  SELECT created_by INTO v_group_creator
  FROM fellowship_groups
  WHERE id = NEW.group_id;
  
  -- Check if the new member is in fellowship with the group creator
  -- (checking both directions of the fellowship relationship)
  SELECT EXISTS (
    SELECT 1 FROM fellowships 
    WHERE (user_id = v_group_creator AND fellow_id = NEW.user_id)
       OR (user_id = NEW.user_id AND fellow_id = v_group_creator)
  ) INTO v_is_in_fellowship;
  
  -- Allow if user is the creator or is in fellowship with creator
  IF NEW.user_id = v_group_creator OR v_is_in_fellowship THEN
    RETURN NEW;
  ELSE
    RAISE EXCEPTION 'User must be in fellowship with group creator to join this group';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to enforce fellowship requirement
DROP TRIGGER IF EXISTS enforce_fellowship_for_groups ON fellowship_group_members;
CREATE TRIGGER enforce_fellowship_for_groups
  BEFORE INSERT ON fellowship_group_members
  FOR EACH ROW
  EXECUTE FUNCTION validate_fellowship_for_group();

-- Update the invite function to only allow inviting fellowship members
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
  v_group_creator UUID;
BEGIN
  v_user_id := auth.uid();
  
  -- Get group creator
  SELECT created_by INTO v_group_creator
  FROM fellowship_groups
  WHERE id = p_group_id;
  
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
    -- Check if user is in fellowship with group creator
    IF EXISTS (
      SELECT 1 FROM fellowships 
      WHERE (user_id = v_group_creator AND fellow_id = v_user_to_invite)
         OR (user_id = v_user_to_invite AND fellow_id = v_group_creator)
    ) THEN
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
    END IF;
  END LOOP;
  
  RETURN QUERY SELECT v_invited_count, true, format('Invited %s fellowship members to the group', v_invited_count)::TEXT;
END;
$$;

-- Function to get groups visible to a user (only from fellowship members)
CREATE OR REPLACE FUNCTION get_visible_fellowship_groups()
RETURNS TABLE(
  group_id UUID,
  group_name VARCHAR(100),
  description TEXT,
  group_type VARCHAR(50),
  created_by UUID,
  creator_name TEXT,
  member_count BIGINT,
  am_member BOOLEAN,
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
    fg.created_by,
    up.display_name as creator_name,
    COUNT(DISTINCT fgm_all.user_id) as member_count,
    EXISTS(
      SELECT 1 FROM fellowship_group_members fgm_me 
      WHERE fgm_me.group_id = fg.id 
      AND fgm_me.user_id = auth.uid() 
      AND fgm_me.is_active = true
    ) as am_member,
    (
      SELECT role FROM fellowship_group_members fgm_role
      WHERE fgm_role.group_id = fg.id 
      AND fgm_role.user_id = auth.uid() 
      AND fgm_role.is_active = true
      LIMIT 1
    ) as my_role,
    fg.created_at
  FROM fellowship_groups fg
  LEFT JOIN user_profiles up ON fg.created_by = up.user_id
  LEFT JOIN fellowship_group_members fgm_all ON fg.id = fgm_all.group_id AND fgm_all.is_active = true
  WHERE 
    -- Show groups where I'm a member
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm 
      WHERE fgm.group_id = fg.id 
      AND fgm.user_id = auth.uid() 
      AND fgm.is_active = true
    )
    OR
    -- Show public groups created by my fellowship members
    (
      NOT fg.is_private 
      AND EXISTS (
        SELECT 1 FROM fellowships f
        WHERE (f.user_id = auth.uid() AND f.fellow_id = fg.created_by)
           OR (f.user_id = fg.created_by AND f.fellow_id = auth.uid())
      )
    )
  GROUP BY fg.id, fg.name, fg.description, fg.group_type, fg.created_by, up.display_name, fg.created_at
  ORDER BY fg.created_at DESC;
END;
$$;

-- Add a function to check if user can see group (for UI filtering)
CREATE OR REPLACE FUNCTION can_user_see_group(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_group RECORD;
  v_is_member BOOLEAN;
  v_is_in_fellowship BOOLEAN;
BEGIN
  -- Get group details
  SELECT * INTO v_group
  FROM fellowship_groups
  WHERE id = p_group_id;
  
  IF v_group IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Check if user is a member
  SELECT EXISTS (
    SELECT 1 FROM fellowship_group_members
    WHERE group_id = p_group_id 
    AND user_id = p_user_id
    AND is_active = true
  ) INTO v_is_member;
  
  IF v_is_member THEN
    RETURN TRUE;
  END IF;
  
  -- Check if user is in fellowship with creator for public groups
  IF NOT v_group.is_private THEN
    SELECT EXISTS (
      SELECT 1 FROM fellowships
      WHERE (user_id = v_group.created_by AND fellow_id = p_user_id)
         OR (user_id = p_user_id AND fellow_id = v_group.created_by)
    ) INTO v_is_in_fellowship;
    
    RETURN v_is_in_fellowship;
  END IF;
  
  RETURN FALSE;
END;
$$ LANGUAGE plpgsql;