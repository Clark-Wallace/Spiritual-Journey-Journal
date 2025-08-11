-- Force fix for fellowship groups visibility issue
-- This is a more aggressive approach

-- 1. First, disable RLS temporarily to fix data
ALTER TABLE fellowship_groups DISABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 2. Make sure EVERY group has its creator as an admin member
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT 
  fg.id as group_id,
  fg.created_by as user_id,
  'admin' as role,
  true as is_active
FROM fellowship_groups fg
WHERE NOT EXISTS (
  SELECT 1 
  FROM fellowship_group_members fgm
  WHERE fgm.group_id = fg.id 
  AND fgm.user_id = fg.created_by
);

-- Update any existing memberships to ensure creator is admin
UPDATE fellowship_group_members fgm
SET role = 'admin', is_active = true
FROM fellowship_groups fg
WHERE fgm.group_id = fg.id 
  AND fgm.user_id = fg.created_by
  AND (fgm.role != 'admin' OR fgm.is_active = false);

-- 3. Drop and recreate the trigger with SECURITY DEFINER
DROP TRIGGER IF EXISTS add_creator_as_admin ON fellowship_groups;
DROP FUNCTION IF EXISTS ensure_creator_is_admin CASCADE;

CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert the creator as admin
  INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
  VALUES (NEW.id, NEW.created_by, 'admin', true);
  
  -- Return the new row
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- If already exists, update to ensure admin
    UPDATE fellowship_group_members 
    SET role = 'admin', is_active = true
    WHERE group_id = NEW.id AND user_id = NEW.created_by;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER add_creator_as_admin
  AFTER INSERT ON fellowship_groups
  FOR EACH ROW
  EXECUTE FUNCTION ensure_creator_is_admin();

-- 4. Re-enable RLS
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 5. Drop ALL existing policies
DO $$ 
DECLARE
  pol record;
BEGIN
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE tablename IN ('fellowship_groups', 'fellowship_group_members')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, 
      CASE 
        WHEN pol.policyname LIKE '%group_members%' THEN 'fellowship_group_members'
        ELSE 'fellowship_groups'
      END);
  END LOOP;
END $$;

-- 6. Create SIMPLE, PERMISSIVE policies
-- For fellowship_groups
CREATE POLICY "Anyone can view groups they created"
  ON fellowship_groups FOR SELECT
  USING (created_by = auth.uid());

CREATE POLICY "Anyone can view groups they are member of"
  ON fellowship_groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_groups.id 
        AND user_id = auth.uid() 
        AND is_active = true
    )
  );

CREATE POLICY "View public groups from fellowship"
  ON fellowship_groups FOR SELECT
  USING (
    is_private = false 
    AND EXISTS (
      SELECT 1 FROM fellowships f
      WHERE (f.user_id = auth.uid() AND f.fellow_id = created_by)
         OR (f.user_id = created_by AND f.fellow_id = auth.uid())
    )
  );

CREATE POLICY "Anyone can create groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Creators can update their groups"
  ON fellowship_groups FOR UPDATE
  USING (created_by = auth.uid());

CREATE POLICY "Creators can delete their groups"
  ON fellowship_groups FOR DELETE
  USING (created_by = auth.uid());

-- For fellowship_group_members
CREATE POLICY "View members - anyone in group"
  ON fellowship_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm2
      WHERE fgm2.group_id = fellowship_group_members.group_id 
        AND fgm2.user_id = auth.uid() 
        AND fgm2.is_active = true
    )
  );

CREATE POLICY "Insert members - self or admin"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid() 
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_members.group_id 
        AND user_id = auth.uid() 
        AND role = 'admin'
    )
  );

CREATE POLICY "Update members - self or admin"
  ON fellowship_group_members FOR UPDATE
  USING (
    user_id = auth.uid() 
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_members.group_id 
        AND user_id = auth.uid() 
        AND role = 'admin'
    )
  );

CREATE POLICY "Delete members - self or admin"
  ON fellowship_group_members FOR DELETE
  USING (
    user_id = auth.uid() 
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_members.group_id 
        AND user_id = auth.uid() 
        AND role = 'admin'
    )
  );

-- 7. Test the view as authenticated user
SET ROLE authenticated;
SELECT 
  'After fix - Groups visible:' as status,
  COUNT(*) as count
FROM fellowship_groups;

SELECT 
  'After fix - Your memberships:' as status,
  COUNT(*) as count
FROM fellowship_group_members
WHERE user_id = auth.uid();

RESET ROLE;

-- 8. Final verification
SELECT 
  fg.id,
  fg.name,
  fg.created_by,
  fg.created_at,
  COUNT(fgm.user_id) as member_count,
  bool_or(fgm.user_id = fg.created_by) as creator_is_member
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
GROUP BY fg.id, fg.name, fg.created_by, fg.created_at
ORDER BY fg.created_at DESC;