-- Fix the RLS policy so public groups are actually visible to everyone

-- 1. Drop the problematic policy
DROP POLICY IF EXISTS "groups_select_public" ON fellowship_groups;

-- 2. Create a proper public groups policy - public means PUBLIC!
CREATE POLICY "groups_select_public"
  ON fellowship_groups FOR SELECT
  USING (is_private = false);  -- That's it! Public groups should be visible to ALL authenticated users

-- 3. The complete SELECT policy set should be:
-- Check existing policies
SELECT 'After fix - SELECT policies:' as status;
SELECT 
    polname as policy_name,
    pg_get_expr(polqual, polrelid) as using_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
AND polcmd = 'r';

-- 4. Test - can we now see all public groups?
SELECT 'Public groups visible after fix:' as status;
SELECT 
    id,
    name,
    description,
    is_private,
    created_by,
    created_at
FROM fellowship_groups
WHERE is_private = false;

-- 5. Also update the main select policy to be clearer
DROP POLICY IF EXISTS "groups_select_creator" ON fellowship_groups;
DROP POLICY IF EXISTS "groups_select_member" ON fellowship_groups;
DROP POLICY IF EXISTS "Users can view groups they're members of or public groups" ON fellowship_groups;

-- Create a single, comprehensive SELECT policy
CREATE POLICY "Users can view groups"
  ON fellowship_groups FOR SELECT
  USING (
    -- Can see if: public OR you created it OR you're a member
    is_private = false 
    OR created_by = auth.uid()
    OR id IN (
      SELECT group_id FROM fellowship_group_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- 6. Verify the final policy
SELECT 'Final SELECT policy:' as status;
SELECT 
    polname as policy_name,
    pg_get_expr(polqual, polrelid) as using_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
AND polcmd = 'r';

-- 7. Test again - should see all public groups now
SELECT 'All public groups (should show 3):' as status;
SELECT id, name, is_private FROM fellowship_groups WHERE is_private = false;

-- 8. Check what an authenticated user would see
SELECT 'All visible groups for authenticated user:' as status;
SELECT id, name, is_private, created_by = auth.uid() as "i_created"
FROM fellowship_groups;