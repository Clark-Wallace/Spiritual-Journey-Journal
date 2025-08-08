-- Check and Fix Reactions Table Structure
-- Run this in Supabase SQL Editor

-- 1. First, let's see what the current table structure is
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'reactions'
ORDER BY ordinal_position;

-- 2. Let's see if there's any data in it
SELECT COUNT(*) as total_reactions FROM reactions;

-- 3. Look at a sample of the data (if any)
SELECT * FROM reactions LIMIT 5;

-- 4. If the table structure is wrong, we might need to recreate it
-- First backup any existing data
CREATE TABLE IF NOT EXISTS reactions_backup AS SELECT * FROM reactions;

-- 5. Drop and recreate the table with correct structure
DROP TABLE IF EXISTS reactions CASCADE;

CREATE TABLE reactions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction VARCHAR(50) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(post_id, user_id, reaction)
);

-- 6. Create indexes
CREATE INDEX idx_reactions_post_id ON reactions(post_id);
CREATE INDEX idx_reactions_user_id ON reactions(user_id);

-- 7. Enable RLS
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- 8. Create policies
CREATE POLICY "Users can view all reactions" ON reactions
  FOR SELECT USING (true);

CREATE POLICY "Users can add their own reactions" ON reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their own reactions" ON reactions
  FOR DELETE USING (auth.uid() = user_id);

-- 9. Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE reactions;

-- 10. Grant permissions
GRANT ALL ON reactions TO authenticated;

-- 11. Verify the new structure
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns 
WHERE table_name = 'reactions'
ORDER BY ordinal_position;

-- 12. Test it works (this will be rolled back)
DO $$
DECLARE
  test_post_id UUID;
  test_user_id UUID;
BEGIN
  -- Get a valid post_id
  SELECT id INTO test_post_id FROM community_posts LIMIT 1;
  -- Get the current user
  test_user_id := auth.uid();
  
  IF test_post_id IS NOT NULL AND test_user_id IS NOT NULL THEN
    -- Try to insert
    INSERT INTO reactions (post_id, user_id, reaction) 
    VALUES (test_post_id, test_user_id, 'test');
    
    -- Check it worked
    IF EXISTS (SELECT 1 FROM reactions WHERE reaction = 'test') THEN
      RAISE NOTICE 'Success! Reactions table is working correctly';
    END IF;
    
    -- Clean up
    DELETE FROM reactions WHERE reaction = 'test';
  ELSE
    RAISE NOTICE 'Could not test - no posts found or user not authenticated';
  END IF;
END $$;

SELECT 'Reactions table has been recreated successfully!' as status;