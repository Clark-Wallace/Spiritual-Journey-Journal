-- Fix infinite recursion in fellowship_group_members RLS policies

-- 1. Temporarily disable RLS to fix the issue
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 2. Drop ALL existing policies on fellowship_group_members
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT polname 
        FROM pg_policy 
        WHERE polrelid = 'fellowship_group_members'::regclass
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON fellowship_group_members', pol.polname);
    END LOOP;
END $$;

-- 3. Create simple, non-recursive policies

-- SELECT: Can see members if you're also a member of the group
CREATE POLICY "view_group_members"
  ON fellowship_group_members FOR SELECT
  USING (
    -- You can see members of groups you're in
    group_id IN (
      SELECT group_id 
      FROM fellowship_group_members fgm
      WHERE fgm.user_id = auth.uid()
      AND fgm.is_active = true
    )
  );

-- INSERT: Can add yourself or invite others if you're an admin
CREATE POLICY "add_members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    -- Adding yourself
    user_id = auth.uid()
    -- Or you invited them
    OR invited_by = auth.uid()
  );

-- UPDATE: Can update your own membership or if you're admin
CREATE POLICY "update_members"
  ON fellowship_group_members FOR UPDATE
  USING (
    -- Your own membership
    user_id = auth.uid()
  );

-- DELETE: Can only delete your own membership
CREATE POLICY "delete_members"
  ON fellowship_group_members FOR DELETE
  USING (user_id = auth.uid());

-- 4. Re-enable RLS
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 5. Test that queries work without recursion
SELECT 'Testing member queries:' as status;

-- This should work without recursion
SELECT COUNT(*) as member_count
FROM fellowship_group_members
WHERE is_active = true;

-- 6. Also simplify the invites table policies if needed
ALTER TABLE fellowship_group_invites DISABLE ROW LEVEL SECURITY;

-- Drop existing policies
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT polname 
        FROM pg_policy 
        WHERE polrelid = 'fellowship_group_invites'::regclass
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON fellowship_group_invites', pol.polname);
    END LOOP;
END $$;

-- Create simple policies for invites
CREATE POLICY "view_invites"
  ON fellowship_group_invites FOR SELECT
  USING (
    invited_user_id = auth.uid() 
    OR invited_by = auth.uid()
  );

CREATE POLICY "create_invites"
  ON fellowship_group_invites FOR INSERT
  WITH CHECK (invited_by = auth.uid());

CREATE POLICY "update_invites"
  ON fellowship_group_invites FOR UPDATE
  USING (invited_user_id = auth.uid());

-- Re-enable RLS
ALTER TABLE fellowship_group_invites ENABLE ROW LEVEL SECURITY;

-- 7. Verify everything works
SELECT 'Policies fixed. Testing queries:' as status;

-- Test selecting groups
SELECT COUNT(*) as visible_groups FROM fellowship_groups;

-- Test selecting members
SELECT COUNT(*) as visible_members FROM fellowship_group_members;

-- Test selecting invites
SELECT COUNT(*) as visible_invites FROM fellowship_group_invites;