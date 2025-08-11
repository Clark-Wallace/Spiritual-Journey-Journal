-- Fix infinite recursion in fellowship_groups RLS policies

-- 1. Temporarily disable RLS to fix the issue
ALTER TABLE fellowship_groups DISABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 2. Drop ALL existing policies to start fresh
DROP POLICY IF EXISTS "Users can view groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can create groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Group admins can update their groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Group admins can delete their groups" ON fellowship_groups;
DROP POLICY IF EXISTS "groups_select_creator" ON fellowship_groups;
DROP POLICY IF EXISTS "groups_select_member" ON fellowship_groups;
DROP POLICY IF EXISTS "groups_select_public" ON fellowship_groups;

-- 3. Create simple, non-recursive policies for fellowship_groups

-- SELECT: Can see public groups OR groups you created OR groups you're a member of
CREATE POLICY "select_groups"
  ON fellowship_groups FOR SELECT
  USING (
    is_private = false  -- Public groups
    OR created_by = auth.uid()  -- Groups you created
    OR EXISTS (  -- Groups you're a member of (no recursion - direct table query)
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_groups.id
      AND fgm.user_id = auth.uid()
      AND fgm.is_active = true
    )
  );

-- INSERT: Authenticated users can create groups
CREATE POLICY "insert_groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL 
    AND created_by = auth.uid()
  );

-- UPDATE: Only group admins can update
CREATE POLICY "update_groups"
  ON fellowship_groups FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_groups.id
      AND fgm.user_id = auth.uid()
      AND fgm.role = 'admin'
      AND fgm.is_active = true
    )
  );

-- DELETE: Only creator can delete
CREATE POLICY "delete_groups"
  ON fellowship_groups FOR DELETE
  USING (created_by = auth.uid());

-- 4. Drop and recreate policies for fellowship_group_members
DROP POLICY IF EXISTS "Members can view group membership" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can be added" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can update members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Users can leave groups (deactivate membership)" ON fellowship_group_members;

-- SELECT: Can see members of groups you're in
CREATE POLICY "select_members"
  ON fellowship_group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members fgm2
      WHERE fgm2.group_id = fellowship_group_members.group_id
      AND fgm2.user_id = auth.uid()
      AND fgm2.is_active = true
    )
  );

-- INSERT: Can add yourself or be added by admin
CREATE POLICY "insert_members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid()  -- Adding yourself
    OR invited_by = auth.uid()  -- You're inviting someone
  );

-- UPDATE: Admins can update, or users can update their own membership
CREATE POLICY "update_members"
  ON fellowship_group_members FOR UPDATE
  USING (
    user_id = auth.uid()  -- Updating your own membership
    OR EXISTS (  -- You're an admin of the group
      SELECT 1 FROM fellowship_group_members fgm
      WHERE fgm.group_id = fellowship_group_members.group_id
      AND fgm.user_id = auth.uid()
      AND fgm.role = 'admin'
      AND fgm.is_active = true
    )
  );

-- 5. Re-enable RLS
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 6. Add memberships for existing groups (if missing)
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT 
    id as group_id,
    created_by as user_id,
    'admin' as role,
    true as is_active
FROM fellowship_groups
WHERE created_by IS NOT NULL
ON CONFLICT (group_id, user_id) DO UPDATE
SET role = 'admin', is_active = true;

-- 7. Test that we can now query without recursion
SELECT 'Groups visible after fix:' as check;
SELECT id, name, is_private, created_by 
FROM fellowship_groups;

-- 8. Test get_my_fellowship_groups
SELECT 'Your groups:' as check;
SELECT * FROM get_my_fellowship_groups();

-- 9. Show memberships
SELECT 'Your memberships:' as check;
SELECT 
    fg.name,
    fgm.role,
    fgm.is_active
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = auth.uid();