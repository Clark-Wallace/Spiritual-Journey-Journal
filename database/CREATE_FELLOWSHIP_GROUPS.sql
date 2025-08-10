-- Fellowship Groups Feature
-- Allows users to create and join fellowship groups (e.g., Men's Group, Women's Group, Bible Study)

-- 1. Create fellowship_groups table
CREATE TABLE IF NOT EXISTS fellowship_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  description TEXT,
  group_type VARCHAR(50) DEFAULT 'general', -- 'mens', 'womens', 'bible_study', 'prayer', 'youth', 'general'
  created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  is_private BOOLEAN DEFAULT false, -- Whether group requires invitation
  max_members INTEGER DEFAULT 50,
  cover_image TEXT, -- Optional group image URL
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create fellowship_group_members table
CREATE TABLE IF NOT EXISTS fellowship_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES fellowship_groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role VARCHAR(20) DEFAULT 'member', -- 'admin', 'moderator', 'member'
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  invited_by UUID REFERENCES auth.users(id),
  is_active BOOLEAN DEFAULT true,
  UNIQUE(group_id, user_id)
);

-- 3. Create fellowship_group_invites table
CREATE TABLE IF NOT EXISTS fellowship_group_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES fellowship_groups(id) ON DELETE CASCADE,
  invited_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'accepted', 'declined'
  message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '7 days'),
  UNIQUE(group_id, invited_user_id)
);

-- 4. Create fellowship_group_posts table (for group-specific content)
CREATE TABLE IF NOT EXISTS fellowship_group_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES fellowship_groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name VARCHAR(255),
  content TEXT NOT NULL,
  post_type VARCHAR(50) DEFAULT 'general',
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_fellowship_group_members_group_id ON fellowship_group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_group_members_user_id ON fellowship_group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_group_posts_group_id ON fellowship_group_posts(group_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_group_invites_invited_user ON fellowship_group_invites(invited_user_id);

-- 6. Enable RLS
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_posts ENABLE ROW LEVEL SECURITY;

-- 7. RLS Policies

-- Fellowship Groups Policies
CREATE POLICY "Users can view groups they're members of or public groups"
  ON fellowship_groups FOR SELECT
  USING (
    NOT is_private 
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
  );

CREATE POLICY "Users can create groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Group admins can update their groups"
  ON fellowship_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
      AND user_id = auth.uid() 
      AND role = 'admin'
      AND is_active = true
    )
  );

CREATE POLICY "Group admins can delete their groups"
  ON fellowship_groups FOR DELETE
  USING (created_by = auth.uid());

-- Fellowship Group Members Policies
CREATE POLICY "Members can view group membership"
  ON fellowship_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id 
      AND fgm.user_id = auth.uid() 
      AND fgm.is_active = true
    )
  );

CREATE POLICY "Admins can add members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_members.group_id 
      AND user_id = auth.uid() 
      AND role IN ('admin', 'moderator')
      AND is_active = true
    )
    OR invited_by = auth.uid()
  );

CREATE POLICY "Admins can update members"
  ON fellowship_group_members FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id 
      AND fgm.user_id = auth.uid() 
      AND fgm.role = 'admin'
      AND fgm.is_active = true
    )
  );

CREATE POLICY "Users can leave groups (deactivate membership)"
  ON fellowship_group_members FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND is_active = false);

-- Fellowship Group Posts Policies
CREATE POLICY "Members can view group posts"
  ON fellowship_group_posts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
  );

CREATE POLICY "Members can create posts"
  ON fellowship_group_posts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
    AND user_id = auth.uid()
  );

CREATE POLICY "Users can update their own posts"
  ON fellowship_group_posts FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own posts or admins can delete any"
  ON fellowship_group_posts FOR DELETE
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND role IN ('admin', 'moderator')
      AND is_active = true
    )
  );

-- Fellowship Group Invites Policies
CREATE POLICY "Users can view their invites"
  ON fellowship_group_invites FOR SELECT
  USING (invited_user_id = auth.uid() OR invited_by = auth.uid());

CREATE POLICY "Group admins/moderators can send invites"
  ON fellowship_group_invites FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_invites.group_id 
      AND user_id = auth.uid() 
      AND role IN ('admin', 'moderator')
      AND is_active = true
    )
  );

CREATE POLICY "Invited users can respond to invites"
  ON fellowship_group_invites FOR UPDATE
  USING (invited_user_id = auth.uid());

-- 8. Create helper functions

-- Function to create a new fellowship group
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
  
  -- Create the group
  INSERT INTO fellowship_groups (name, description, group_type, created_by, is_private)
  VALUES (p_name, p_description, p_group_type, v_user_id, p_is_private)
  RETURNING id INTO v_group_id;
  
  -- Add creator as admin
  INSERT INTO fellowship_group_members (group_id, user_id, role)
  VALUES (v_group_id, v_user_id, 'admin');
  
  RETURN QUERY SELECT v_group_id, true, 'Group created successfully'::TEXT;
END;
$$;

-- Function to invite users to a group
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

-- Function to respond to group invite
CREATE OR REPLACE FUNCTION respond_to_group_invite(
  p_invite_id UUID,
  p_response VARCHAR(20) -- 'accepted' or 'declined'
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
    VALUES (v_invite.group_id, v_user_id, 'member', v_invite.invited_by);
    
    RETURN QUERY SELECT true, 'Successfully joined the group'::TEXT;
  ELSE
    RETURN QUERY SELECT true, 'Invite declined'::TEXT;
  END IF;
END;
$$;

-- Function to get user's groups
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

-- Enable realtime for group posts
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_group_posts;
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_group_members;