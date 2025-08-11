-- Fix the INSERT policy that's blocking group creation

-- 1. Check current INSERT policies on fellowship_groups
SELECT 'Current INSERT policies:' as check;
SELECT 
    polname as policy_name,
    pg_get_expr(polwithcheck, polrelid) as with_check_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
AND polcmd = 'a'; -- INSERT

-- 2. Drop the problematic INSERT policy
DROP POLICY IF EXISTS "Users can create groups" ON fellowship_groups;
DROP POLICY IF EXISTS "groups_insert_fellowship" ON fellowship_groups;
DROP POLICY IF EXISTS "Users must be in fellowship to create groups" ON fellowship_groups;

-- 3. Create a simple INSERT policy - any authenticated user can create a group
CREATE POLICY "Users can create groups"
  ON fellowship_groups FOR INSERT
  WITH CHECK (
    -- Just check that the user is authenticated and setting themselves as creator
    auth.uid() IS NOT NULL 
    AND created_by = auth.uid()
  );

-- 4. Verify the new policy
SELECT 'New INSERT policy:' as check;
SELECT 
    polname as policy_name,
    pg_get_expr(polwithcheck, polrelid) as with_check_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
AND polcmd = 'a';

-- 5. Test creating a group with the fixed policy
DO $$
DECLARE
    v_group_id UUID := gen_random_uuid();
    v_user_id UUID := 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;
BEGIN
    -- Try to insert
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (v_group_id, 'Policy Test Group ' || NOW()::text, 'Testing after policy fix', 'general', v_user_id, false);
    
    RAISE NOTICE 'SUCCESS: Group created with ID: %', v_group_id;
    
    -- Add membership
    INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
    VALUES (v_group_id, v_user_id, 'admin', true);
    
    RAISE NOTICE 'SUCCESS: Membership added';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERROR: %', SQLERRM;
END $$;

-- 6. Also check and fix INSERT policy on fellowship_group_members
SELECT 'Current INSERT policies on fellowship_group_members:' as check;
SELECT 
    polname as policy_name,
    pg_get_expr(polwithcheck, polrelid) as with_check_clause
FROM pg_policy
WHERE polrelid = 'fellowship_group_members'::regclass
AND polcmd = 'a';

-- Drop any problematic policies
DROP POLICY IF EXISTS "Admins can add members" ON fellowship_group_members;
DROP POLICY IF EXISTS "Users can add themselves as members" ON fellowship_group_members;

-- Create a better policy for members
CREATE POLICY "Members can be added"
  ON fellowship_group_members FOR INSERT
  WITH CHECK (
    -- Can add if: you're adding yourself OR you're an admin/mod of the group OR it's during group creation
    user_id = auth.uid()
    OR invited_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members existing
      WHERE existing.group_id = fellowship_group_members.group_id
      AND existing.user_id = auth.uid()
      AND existing.role IN ('admin', 'moderator')
      AND existing.is_active = true
    )
    -- Special case: allow during group creation when creator is adding themselves
    OR (
      user_id = (SELECT created_by FROM fellowship_groups WHERE id = group_id)
      AND NOT EXISTS (
        SELECT 1 FROM fellowship_group_members
        WHERE group_id = fellowship_group_members.group_id
      )
    )
  );

-- 7. Test the complete flow again
SELECT 'Testing complete group creation:' as check;
SELECT * FROM create_fellowship_group_test('Final Test Group', 'Should work now', 'general', false);

-- 8. Show all groups to confirm they're being created
SELECT 'All groups after fixes:' as check;
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
ORDER BY created_at DESC;