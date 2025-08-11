-- Comprehensive fix for Fellowship Groups RLS policies
-- This fixes the issue where groups disappear after refresh

-- First, let's check what groups exist
SELECT id, name, created_by, created_at FROM fellowship_groups;

-- Check what members exist
SELECT * FROM fellowship_group_members;

-- Drop all existing RLS policies to start fresh
DROP POLICY IF EXISTS "Users can view groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can view groups they're members of or public groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can create groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can update their own groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can delete their own groups" ON fellowship_groups;

DROP POLICY IF EXISTS "Members can view group members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can add members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can leave groups" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can remove members" ON fellowship_group_members;

-- Enable RLS on tables
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- Create comprehensive policies for fellowship_groups
-- View policy: Can see groups you created OR are a member of OR public groups from fellowship
CREATE POLICY "View groups - comprehensive"
  ON fellowship_groups FOR SELECT
  USING (
    -- You created the group
    created_by = auth.uid()
    OR
    -- You are an active member
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
    OR
    -- Public group from someone in your fellowship
    (
      is_private = false 
      AND EXISTS (
        SELECT 1 FROM fellowships f
        WHERE (f.user_id = auth.uid() AND f.fellow_id = created_by)
           OR (f.user_id = created_by AND f.fellow_id = auth.uid())
      )
    )
  );

-- Create policy
CREATE POLICY "Create groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

-- Update policy (only creator or admin can update)
CREATE POLICY "Update groups"
  ON fellowship_groups FOR UPDATE
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
      AND user_id = auth.uid() 
      AND role = 'admin'
      AND is_active = true
    )
  );

-- Delete policy (only creator can delete)
CREATE POLICY "Delete groups"
  ON fellowship_groups FOR DELETE
  USING (created_by = auth.uid());

-- Policies for fellowship_group_members
-- View members
CREATE POLICY "View group members"
  ON fellowship_group_members FOR SELECT
  USING (
    -- Can see members if you're in the group
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm2
      WHERE fgm2.group_id = fellowship_group_members.group_id 
      AND fgm2.user_id = auth.uid() 
      AND fgm2.is_active = true
    )
    OR
    -- Or if you created the group
    EXISTS (
      SELECT 1 FROM fellowship_groups fg
      WHERE fg.id = fellowship_group_members.group_id 
      AND fg.created_by = auth.uid()
    )
  );

-- Insert members (anyone can join public groups, admins can add to any)
CREATE POLICY "Join or add members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    -- Adding yourself to a public group
    (
      user_id = auth.uid()
      AND EXISTS (
        SELECT 1 FROM fellowship_groups fg
        WHERE fg.id = group_id 
        AND fg.is_private = false
      )
    )
    OR
    -- Admin adding someone
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id 
      AND fgm.user_id = auth.uid() 
      AND fgm.role IN ('admin', 'moderator')
      AND fgm.is_active = true
    )
    OR
    -- Creator adding someone
    EXISTS (
      SELECT 1 FROM fellowship_groups fg
      WHERE fg.id = group_id 
      AND fg.created_by = auth.uid()
    )
  );

-- Update members (admins can update roles)
CREATE POLICY "Update member roles"
  ON fellowship_group_members FOR UPDATE
  USING (
    -- Updating yourself (to leave)
    user_id = auth.uid()
    OR
    -- Admin updating
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id 
      AND fgm.user_id = auth.uid() 
      AND fgm.role = 'admin'
      AND fgm.is_active = true
    )
  );

-- Delete members
CREATE POLICY "Remove members"
  ON fellowship_group_members FOR DELETE
  USING (
    -- Removing yourself
    user_id = auth.uid()
    OR
    -- Admin removing
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id 
      AND fgm.user_id = auth.uid() 
      AND fgm.role = 'admin'
      AND fgm.is_active = true
    )
  );

-- Fix the trigger that adds creator as admin (ensure it's working)
CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER AS $$
BEGIN
  -- Always add creator as admin member
  INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
  VALUES (NEW.id, NEW.created_by, 'admin', true)
  ON CONFLICT (group_id, user_id) 
  DO UPDATE SET 
    role = 'admin',
    is_active = true;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS add_creator_as_admin ON fellowship_groups;
CREATE TRIGGER add_creator_as_admin
  AFTER INSERT ON fellowship_groups
  FOR EACH ROW
  EXECUTE FUNCTION ensure_creator_is_admin();

-- Fix any existing groups that don't have their creator as admin
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT fg.id, fg.created_by, 'admin', true
FROM fellowship_groups fg
WHERE NOT EXISTS (
  SELECT 1 FROM fellowship_group_members fgm
  WHERE fgm.group_id = fg.id 
  AND fgm.user_id = fg.created_by
)
ON CONFLICT (group_id, user_id) 
DO UPDATE SET 
  role = 'admin',
  is_active = true;

-- Grant necessary permissions
GRANT ALL ON fellowship_groups TO authenticated;
GRANT ALL ON fellowship_group_members TO authenticated;
GRANT ALL ON fellowship_group_invites TO authenticated;
GRANT ALL ON fellowship_group_posts TO authenticated;

-- Enable realtime for these tables
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS fellowship_groups;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS fellowship_group_members;
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_groups;
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_group_members;

-- Verify the setup
SELECT 
  fg.id,
  fg.name,
  fg.created_by,
  fgm.user_id as member_id,
  fgm.role,
  fgm.is_active
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
ORDER BY fg.created_at DESC;