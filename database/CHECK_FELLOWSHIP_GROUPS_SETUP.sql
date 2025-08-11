-- Diagnostic script to check what Fellowship Groups components exist

-- 1. Check if tables exist
SELECT 
    'fellowship_groups' as table_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'fellowship_groups'
    ) as exists
UNION ALL
SELECT 
    'fellowship_group_members' as table_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'fellowship_group_members'
    ) as exists
UNION ALL
SELECT 
    'fellowship_group_invites' as table_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'fellowship_group_invites'
    ) as exists
UNION ALL
SELECT 
    'fellowship_group_posts' as table_name,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'fellowship_group_posts'
    ) as exists;

-- 2. Check if RPC functions exist
SELECT 
    proname as function_name,
    pg_get_function_identity_arguments(oid) as arguments
FROM pg_proc
WHERE proname IN (
    'create_fellowship_group',
    'create_fellowship_group_safe',
    'invite_to_fellowship_group',
    'respond_to_group_invite',
    'get_my_fellowship_groups'
)
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;

-- 3. Check RLS policies on fellowship_groups table
SELECT 
    polname as policy_name,
    polcmd as command,
    CASE polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        ELSE 'ALL'
    END as operation
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
ORDER BY polname;

-- 4. Check if any groups exist
SELECT COUNT(*) as group_count FROM fellowship_groups;

-- 5. Check for any errors in fellowship_groups structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'fellowship_groups'
ORDER BY ordinal_position;