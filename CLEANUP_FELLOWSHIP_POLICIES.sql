-- Clean up duplicate fellowship policies and ensure correct ones are in place

-- Drop all existing policies on fellowships table
DROP POLICY IF EXISTS "Users can add fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can delete own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can insert own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can remove own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can view fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can view own fellowships" ON fellowships;

-- Create clean policies for fellowships
-- 1. Anyone can view all fellowships (needed for checking if fellowship exists)
CREATE POLICY "Users can view all fellowships" 
ON fellowships FOR SELECT 
USING (true);

-- 2. Users can only insert fellowships where they are the user_id
CREATE POLICY "Users can insert own fellowships" 
ON fellowships FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- 3. Users can only delete fellowships where they are the user_id
CREATE POLICY "Users can delete own fellowships" 
ON fellowships FOR DELETE 
USING (auth.uid() = user_id);

-- Now run the trigger creation to ensure mutual fellowships are created
-- This was already in CREATE_FELLOWSHIP_TRIGGER.sql but let's ensure it exists
CREATE OR REPLACE FUNCTION create_mutual_fellowship()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if the reverse fellowship already exists
  IF NOT EXISTS (
    SELECT 1 FROM fellowships 
    WHERE user_id = NEW.fellow_id 
    AND fellow_id = NEW.user_id
  ) THEN
    -- Create the reverse fellowship
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES (NEW.fellow_id, NEW.user_id)
    ON CONFLICT (user_id, fellow_id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate the trigger
DROP TRIGGER IF EXISTS create_mutual_fellowship_trigger ON fellowships;

CREATE TRIGGER create_mutual_fellowship_trigger
AFTER INSERT ON fellowships
FOR EACH ROW
EXECUTE FUNCTION create_mutual_fellowship();

-- Verify the final policies
SELECT tablename, policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'fellowships'
ORDER BY policyname;