-- Direct test to see what's preventing group creation

-- 1. Check if the table has any groups at all
SELECT COUNT(*) as total_groups FROM fellowship_groups;

-- 2. Try to insert a group directly (not through function)
DO $$
DECLARE
    test_id UUID := gen_random_uuid();
    test_user_id UUID := 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;
BEGIN
    -- Try direct insert
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (test_id, 'Direct Test ' || NOW()::text, 'Testing direct insert', 'general', test_user_id, false);
    
    RAISE NOTICE 'Group inserted successfully with ID: %', test_id;
    
    -- Check if it exists
    IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = test_id) THEN
        RAISE NOTICE 'Group exists in table!';
    ELSE
        RAISE NOTICE 'Group NOT found in table after insert!';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error during insert: %', SQLERRM;
        RAISE NOTICE 'SQLSTATE: %', SQLSTATE;
END $$;

-- 3. Check if there are any RLS policies preventing inserts
SELECT 
    polname as policy_name,
    polcmd,
    CASE polcmd
        WHEN 'r' THEN 'SELECT'
        WHEN 'a' THEN 'INSERT'
        WHEN 'w' THEN 'UPDATE'
        WHEN 'd' THEN 'DELETE'
        ELSE 'ALL'
    END as operation,
    polpermissive as is_permissive,
    pg_get_expr(polqual, polrelid) as using_clause,
    pg_get_expr(polwithcheck, polrelid) as with_check_clause
FROM pg_policy
WHERE polrelid = 'fellowship_groups'::regclass
ORDER BY polcmd;

-- 4. Check if RLS is enabled
SELECT 
    relname as table_name,
    relrowsecurity as rls_enabled,
    relforcerowsecurity as rls_forced
FROM pg_class
WHERE relname = 'fellowship_groups';

-- 5. Try with RLS disabled temporarily (for testing)
ALTER TABLE fellowship_groups DISABLE ROW LEVEL SECURITY;

-- Try insert again
DO $$
DECLARE
    test_id UUID := gen_random_uuid();
    test_user_id UUID := 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;
BEGIN
    INSERT INTO fellowship_groups (id, name, description, group_type, created_by, is_private)
    VALUES (test_id, 'RLS Disabled Test ' || NOW()::text, 'Testing with RLS off', 'general', test_user_id, false);
    
    RAISE NOTICE 'With RLS disabled - Group inserted with ID: %', test_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'With RLS disabled - Error: %', SQLERRM;
END $$;

-- Re-enable RLS
ALTER TABLE fellowship_groups ENABLE ROW LEVEL SECURITY;

-- 6. Check what groups exist now
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
ORDER BY created_at DESC
LIMIT 10;