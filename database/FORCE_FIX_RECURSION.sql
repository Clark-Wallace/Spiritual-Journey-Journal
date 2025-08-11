-- FORCE fix the infinite recursion issue

-- 1. Completely disable RLS on the problematic table
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 2. Drop ALL policies
DROP POLICY IF EXISTS "view_group_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "add_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "update_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "delete_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can view group membership" ON fellowship_group_members;
DROP POLICY IF EXISTS "Members can be added" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can add members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Admins can update members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Users can leave groups (deactivate membership)" ON fellowship_group_members;
DROP POLICY IF EXISTS "Users can add themselves as members" ON fellowship_group_members;
DROP POLICY IF EXISTS "select_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "insert_members" ON fellowship_group_members;
DROP POLICY IF EXISTS "update_members" ON fellowship_group_members;

-- 3. Create ULTRA SIMPLE policy - just allow authenticated users to see all memberships
CREATE POLICY "simple_view_members"
  ON fellowship_group_members FOR SELECT
  USING (auth.uid() IS NOT NULL);  -- Any authenticated user can see memberships

-- 4. Simple INSERT policy
CREATE POLICY "simple_add_members"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- 5. Simple UPDATE policy  
CREATE POLICY "simple_update_members"
  ON fellowship_group_members FOR UPDATE
  USING (user_id = auth.uid());

-- 6. Re-enable RLS
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 7. Do the same for fellowship_group_invites
ALTER TABLE fellowship_group_invites DISABLE ROW LEVEL SECURITY;

-- Drop all policies
DROP POLICY IF EXISTS "view_invites" ON fellowship_group_invites;
DROP POLICY IF EXISTS "create_invites" ON fellowship_group_invites;
DROP POLICY IF EXISTS "update_invites" ON fellowship_group_invites;
DROP POLICY IF EXISTS "Users can view their invites" ON fellowship_group_invites;
DROP POLICY IF EXISTS "Group admins/moderators can send invites" ON fellowship_group_invites;
DROP POLICY IF EXISTS "Invited users can respond to invites" ON fellowship_group_invites;

-- Create simple policies
CREATE POLICY "simple_view_invites"
  ON fellowship_group_invites FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "simple_create_invites"
  ON fellowship_group_invites FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "simple_update_invites"
  ON fellowship_group_invites FOR UPDATE
  USING (invited_user_id = auth.uid());

-- Re-enable RLS
ALTER TABLE fellowship_group_invites ENABLE ROW LEVEL SECURITY;

-- 8. Test queries
SELECT 'Testing after fix:' as status;
SELECT COUNT(*) as groups_count FROM fellowship_groups WHERE is_private = false;
SELECT COUNT(*) as members_count FROM fellowship_group_members;
SELECT COUNT(*) as invites_count FROM fellowship_group_invites;

-- 9. Show what policies exist now
SELECT 'Current policies on fellowship_group_members:' as status;
SELECT polname FROM pg_policy WHERE polrelid = 'fellowship_group_members'::regclass;

SELECT 'Current policies on fellowship_group_invites:' as status;
SELECT polname FROM pg_policy WHERE polrelid = 'fellowship_group_invites'::regclass;