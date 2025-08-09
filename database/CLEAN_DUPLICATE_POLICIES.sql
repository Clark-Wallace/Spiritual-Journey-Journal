-- Clean up duplicate RLS policies on fellowship_requests table

-- First, drop ALL existing policies
DROP POLICY IF EXISTS "Users can cancel sent requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can create requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can send requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update received requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update requests sent to them" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can view own requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can view relevant requests" ON fellowship_requests;

-- Now create clean, single policies for each operation
-- 1. SELECT: Users can view requests they sent or received
CREATE POLICY "Users can view relevant requests" 
ON fellowship_requests FOR SELECT 
USING (
  auth.uid() = from_user_id OR 
  auth.uid() = to_user_id
);

-- 2. INSERT: Users can only create requests from themselves
CREATE POLICY "Users can create requests" 
ON fellowship_requests FOR INSERT 
WITH CHECK (auth.uid() = from_user_id);

-- 3. UPDATE: Users can update requests sent TO them (for accepting/declining)
CREATE POLICY "Users can update requests sent to them" 
ON fellowship_requests FOR UPDATE 
USING (auth.uid() = to_user_id)
WITH CHECK (auth.uid() = to_user_id);

-- 4. UPDATE: Users can also cancel their own sent requests
CREATE POLICY "Users can cancel own requests" 
ON fellowship_requests FOR UPDATE 
USING (auth.uid() = from_user_id AND status = 'pending')
WITH CHECK (auth.uid() = from_user_id AND status = 'cancelled');

-- Verify the policies are clean now
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'fellowship_requests'
ORDER BY policyname;

-- Now test creating a request
-- First get the user IDs
SELECT user_id, display_name 
FROM user_profiles 
WHERE display_name LIKE '%Clark%';

-- Check if any requests exist
SELECT * FROM fellowship_requests;

-- Count of requests
SELECT COUNT(*) as total_requests FROM fellowship_requests;