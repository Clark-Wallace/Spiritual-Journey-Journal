-- Fix the infinite recursion in RLS policies

-- 1. First, drop ALL policies on both tables to start clean
DROP POLICY IF EXISTS "View groups - comprehensive" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can view groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can view groups they're members of or public groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Anyone can view groups they created" ON fellowship_groups;
DROP POLICY IF EXISTS "Anyone can view groups they are member of" ON fellowship_groups;
DROP POLICY IF EXISTS "View public groups from fellowship" ON fellowship_groups;
DROP POLICY IF EXISTS "Create groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Anyone can create groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Update groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Creators can update their groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Delete groups" ON fellowship_groups;
DROP POLICY IF EXISTS "Creators can delete their groups" ON fellowship_groups;

DROP POLICY IF EXISTS "View group members" ON fellowship_group_members;
DROP POLICY IF EXISTS "View members - anyone in group" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can view group members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Join or add members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Insert members - self or admin" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can add members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Update member roles" ON fellowship_group_members;
DROP POLICY IF EXISTS "Update members - self or admin" ON fellowship_group_members;
DROP POLICY IF EXISTS "Remove members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Delete members - self or admin" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can leave groups" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can remove members" ON fellowship_group_members;

-- 2. Temporarily disable RLS to fix data
ALTER TABLE fellowship_groups DISABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 3. Ensure all creators are members
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT 
  fg.id,
  fg.created_by,
  'admin',
  true
FROM fellowship_groups fg
WHERE NOT EXISTS (
  SELECT 1 FROM fellowship_group_members fgm
  WHERE fgm.group_id = fg.id AND fgm.user_id = fg.created_by
)
ON CONFLICT (group_id, user_id) 
DO UPDATE SET role = 'admin', is_active = true;

-- 4. Re-enable RLS
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 5. Create simple, non-recursive policies for fellowship_groups
CREATE POLICY "groups_select_creator"
  ON fellowship_groups FOR SELECT
  USING (created_by = auth.uid());

CREATE POLICY "groups_select_member"
  ON fellowship_groups FOR SELECT
  USING (
    id IN (
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "groups_select_public"
  ON fellowship_groups FOR SELECT
  USING (
    is_private = false 
    AND created_by IN (
      SELECT fellow_id FROM fellowships WHERE user_id = auth.uid()
      UNION
      SELECT user_id FROM fellowships WHERE fellow_id = auth.uid()
    )
  );

CREATE POLICY "groups_insert"
  ON fellowship_groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "groups_update"
  ON fellowship_groups FOR UPDATE
  USING (created_by = auth.uid());

CREATE POLICY "groups_delete"
  ON fellowship_groups FOR DELETE
  USING (created_by = auth.uid());

-- 6. Create simple, non-recursive policies for fellowship_group_members
-- Use a subquery instead of EXISTS to avoid recursion
CREATE POLICY "members_select"
  ON fellowship_group_members FOR SELECT
  USING (
    group_id IN (
      -- Groups you created
      SELECT id FROM fellowship_groups WHERE created_by = auth.uid()
      UNION
      -- Groups you're a member of (check directly in same table)
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "members_insert_self"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND group_id IN (
      SELECT id FROM fellowship_groups WHERE is_private = false
    )
  );

CREATE POLICY "members_insert_admin"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    group_id IN (
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() 
      AND role = 'admin' 
      AND is_active = true
    )
  );

CREATE POLICY "members_update_self"
  ON fellowship_group_members FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "members_update_admin"
  ON fellowship_group_members FOR UPDATE
  USING (
    group_id IN (
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() 
      AND role = 'admin' 
      AND is_active = true
    )
  );

CREATE POLICY "members_delete_self"
  ON fellowship_group_members FOR DELETE
  USING (user_id = auth.uid());

CREATE POLICY "members_delete_admin"
  ON fellowship_group_members FOR DELETE
  USING (
    group_id IN (
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() 
      AND role = 'admin' 
      AND is_active = true
    )
  );

-- 7. Test what we can see
SELECT 
  'Groups in database:' as check,
  COUNT(*) as total,
  COUNT(DISTINCT created_by) as unique_creators
FROM fellowship_groups;

SELECT 
  'Memberships in database:' as check,
  COUNT(*) as total,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT group_id) as unique_groups
FROM fellowship_group_members;

-- 8. Verify all groups have their creator as member
SELECT 
  fg.id,
  fg.name,
  fg.created_by,
  CASE 
    WHEN fgm.user_id IS NOT NULL THEN '✅ Creator is member'
    ELSE '❌ Creator NOT member'
  END as status,
  fgm.role
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm 
  ON fg.id = fgm.group_id AND fg.created_by = fgm.user_id
ORDER BY fg.created_at DESC;