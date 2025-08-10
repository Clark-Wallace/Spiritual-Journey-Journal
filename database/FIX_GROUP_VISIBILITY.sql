-- Fix Fellowship Groups Visibility Issues

-- First, check if there are any groups in the table
SELECT id, name, created_by, created_at FROM fellowship_groups;

-- Check if there are any group members
SELECT * FROM fellowship_group_members;

-- Fix the RLS policies for fellowship_groups table
DROP POLICY IF EXISTS "Users can view groups they're members of or public groups" ON fellowship_groups;

-- Create a simpler, more permissive policy for viewing groups
CREATE POLICY "Users can view groups"
  ON fellowship_groups FOR SELECT
  USING (
    -- Can see groups where you are a member
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
    OR
    -- Can see groups you created
    created_by = auth.uid()
    OR
    -- Can see public groups from fellowship members
    (
      NOT is_private 
      AND EXISTS (
        SELECT 1 FROM fellowships f
        WHERE (f.user_id = auth.uid() AND f.fellow_id = created_by)
           OR (f.user_id = created_by AND f.fellow_id = auth.uid())
      )
    )
  );

-- Fix the get_my_fellowship_groups function to be simpler
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
    COALESCE(fgm.role, 'none') as my_role,
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

-- Ensure the user who creates a group is added as admin
-- (This might have been missed)
CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER AS $$
BEGIN
  -- Add creator as admin member if not already added
  INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
  VALUES (NEW.id, NEW.created_by, 'admin', true)
  ON CONFLICT (group_id, user_id) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-add creator as admin
DROP TRIGGER IF EXISTS add_creator_as_admin ON fellowship_groups;
CREATE TRIGGER add_creator_as_admin
  AFTER INSERT ON fellowship_groups
  FOR EACH ROW
  EXECUTE FUNCTION ensure_creator_is_admin();

-- If you have existing groups without members, fix them
-- This will add the creators as admins for any groups missing that relationship
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT fg.id, fg.created_by, 'admin', true
FROM fellowship_groups fg
WHERE NOT EXISTS (
  SELECT 1 FROM fellowship_group_members fgm
  WHERE fgm.group_id = fg.id AND fgm.user_id = fg.created_by
)
ON CONFLICT (group_id, user_id) DO NOTHING;

-- Grant permissions
GRANT ALL ON fellowship_groups TO authenticated;
GRANT ALL ON fellowship_group_members TO authenticated;
GRANT ALL ON fellowship_group_posts TO authenticated;
GRANT ALL ON fellowship_group_invites TO authenticated;