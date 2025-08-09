-- Test sending a fellowship request directly

-- 1. First, get the user IDs for Clark AI and Clark Wallace
SELECT user_id, display_name 
FROM user_profiles 
WHERE display_name LIKE '%Clark%';

-- 2. Check if fellowship_requests table exists and has any data
SELECT COUNT(*) as total_requests FROM fellowship_requests;

-- 3. Try to insert a test request directly (replace the IDs with actual ones from step 1)
-- Replace 'CLARK_AI_ID' with Clark AI's actual user_id
-- Replace 'CLARK_WALLACE_ID' with Clark Wallace's actual user_id
/*
INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
VALUES ('CLARK_AI_ID', 'CLARK_WALLACE_ID', 'pending')
ON CONFLICT (from_user_id, to_user_id) DO UPDATE
SET status = 'pending', created_at = NOW();
*/

-- 4. Test the RPC function (replace with actual IDs)
-- SELECT * FROM send_fellowship_request('CLARK_AI_ID', 'CLARK_WALLACE_ID');

-- 5. Check if there are any errors in the fellowship_requests table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'fellowship_requests'
ORDER BY ordinal_position;

-- 6. Check if RLS policies might be blocking inserts
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
WHERE tablename = 'fellowship_requests'
ORDER BY policyname;