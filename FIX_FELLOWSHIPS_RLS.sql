-- Fix RLS policies for fellowships table
-- This allows users to manage their own fellowships

-- First, ensure RLS is enabled
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can insert own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can delete own fellowships" ON fellowships;

-- Create new policies
-- Allow users to view all fellowships (needed for checking if fellowship exists)
CREATE POLICY "Users can view fellowships" 
ON fellowships FOR SELECT 
USING (true);

-- Allow users to create fellowships where they are the user
CREATE POLICY "Users can insert own fellowships" 
ON fellowships FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own fellowships
CREATE POLICY "Users can delete own fellowships" 
ON fellowships FOR DELETE 
USING (auth.uid() = user_id);

-- Grant necessary permissions
GRANT ALL ON fellowships TO authenticated;

-- Also fix the fellowship_requests table while we're at it
ALTER TABLE fellowship_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can insert requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update own requests" ON fellowship_requests;

-- Create policies for fellowship_requests
CREATE POLICY "Users can view relevant requests" 
ON fellowship_requests FOR SELECT 
USING (
  auth.uid() = from_user_id OR 
  auth.uid() = to_user_id
);

CREATE POLICY "Users can create requests" 
ON fellowship_requests FOR INSERT 
WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "Users can update requests sent to them" 
ON fellowship_requests FOR UPDATE 
USING (auth.uid() = to_user_id)
WITH CHECK (auth.uid() = to_user_id);

-- Grant permissions
GRANT ALL ON fellowship_requests TO authenticated;

-- Verify the policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies 
WHERE tablename IN ('fellowships', 'fellowship_requests')
ORDER BY tablename, policyname;