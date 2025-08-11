-- Check why public groups aren't showing in Discover tab

-- 1. Check all public groups
SELECT 'Public groups in database:' as check;
SELECT 
    id,
    name,
    description,
    group_type,
    is_private,
    created_by,
    created_at
FROM fellowship_groups
WHERE is_private = false
ORDER BY created_at DESC;

-- 2. Check if user_profiles table exists and has data
SELECT 'User profiles check:' as check;
SELECT COUNT(*) as profile_count FROM user_profiles;

-- 3. Check if your user has a profile
SELECT 'Your user profile:' as check;
SELECT * FROM user_profiles 
WHERE user_id = 'a43ff393-dde1-4001-b667-23f518e72499';

-- 4. Try the exact query the component uses (without the profile join)
SELECT 'Query without profile join:' as check;
SELECT
    id,
    name,
    description,
    group_type,
    created_by,
    created_at
FROM fellowship_groups
WHERE is_private = false
ORDER BY created_at DESC;

-- 5. Try with the profile join (like the component does)
SELECT 'Query with profile join (LEFT JOIN):' as check;
SELECT
    fg.id,
    fg.name,
    fg.description,
    fg.group_type,
    fg.created_by,
    fg.created_at,
    up.display_name
FROM fellowship_groups fg
LEFT JOIN user_profiles up ON up.user_id = fg.created_by
WHERE fg.is_private = false
ORDER BY fg.created_at DESC;

-- 6. Check what the component's exact query returns
SELECT 'Component query simulation:' as check;
SELECT
    fg.id,
    fg.name,
    fg.description,
    fg.group_type,
    fg.created_by,
    fg.created_at,
    up.display_name
FROM fellowship_groups fg
LEFT JOIN user_profiles up ON fg.created_by = up.user_id
WHERE fg.is_private = false
ORDER BY fg.created_at DESC;

-- 7. Check RLS on fellowship_groups for SELECT
SELECT 'SELECT policy on fellowship_groups:' as check;
SELECT 
    polname as policy_name,
    pg_get_expr(polqual, polrelid) as using_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
AND polcmd = 'r'; -- SELECT