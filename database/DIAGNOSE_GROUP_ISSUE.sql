-- Diagnostic script to understand why groups disappear

-- 1. Check what groups exist in the database
SELECT 
  'Total groups in database:' as check,
  COUNT(*) as count
FROM fellowship_groups;

SELECT 
  id,
  name,
  created_by,
  is_private,
  created_at
FROM fellowship_groups
ORDER BY created_at DESC;

-- 2. Check group members
SELECT 
  'Total memberships:' as check,
  COUNT(*) as count
FROM fellowship_group_members;

SELECT 
  fgm.group_id,
  fg.name as group_name,
  fgm.user_id,
  fgm.role,
  fgm.is_active,
  fgm.joined_at
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
ORDER BY fgm.joined_at DESC;

-- 3. Check current user
SELECT 
  'Current user ID:' as info,
  auth.uid() as user_id;

-- 4. Check what the current user SHOULD be able to see
SELECT 
  'Groups where you are creator:' as check,
  COUNT(*) as count
FROM fellowship_groups
WHERE created_by = auth.uid();

SELECT 
  'Groups where you are a member:' as check,
  COUNT(*) as count
FROM fellowship_group_members
WHERE user_id = auth.uid() AND is_active = true;

-- 5. Test the RLS policies directly
-- This simulates what the app sees
SET ROLE authenticated;
SELECT 
  'Groups visible with RLS:' as check,
  COUNT(*) as count
FROM fellowship_groups;

SELECT 
  id,
  name,
  created_by,
  CASE 
    WHEN created_by = auth.uid() THEN 'You created this'
    ELSE 'Created by someone else'
  END as creator_status
FROM fellowship_groups;

-- 6. Check if the trigger is working
SELECT 
  'Triggers on fellowship_groups:' as check,
  tgname as trigger_name
FROM pg_trigger 
WHERE tgrelid = 'fellowship_groups'::regclass;

-- 7. Reset to superuser to see everything again
RESET ROLE;

-- 8. Final check - are creators being added as members?
SELECT 
  fg.id as group_id,
  fg.name as group_name,
  fg.created_by,
  CASE 
    WHEN fgm.user_id IS NULL THEN '❌ Creator NOT a member!'
    ELSE '✅ Creator is a member'
  END as member_status,
  fgm.role
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm 
  ON fg.id = fgm.group_id 
  AND fg.created_by = fgm.user_id;

-- 9. Check RLS policies
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename IN ('fellowship_groups', 'fellowship_group_members')
ORDER BY tablename, policyname;