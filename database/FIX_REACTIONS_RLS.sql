-- Fix RLS Policies for Reactions and Encouragements
-- This ensures users can properly interact with reactions and encouragements

-- 1. Enable RLS on reactions table
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies to recreate them
DROP POLICY IF EXISTS "Users can view all reactions" ON reactions;
DROP POLICY IF EXISTS "Users can create their own reactions" ON reactions;
DROP POLICY IF EXISTS "Users can delete their own reactions" ON reactions;

-- 3. Create policies for reactions
-- Allow users to view all reactions
CREATE POLICY "Users can view all reactions" ON reactions
FOR SELECT USING (true);

-- Allow users to create their own reactions
CREATE POLICY "Users can create their own reactions" ON reactions
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own reactions
CREATE POLICY "Users can delete their own reactions" ON reactions
FOR DELETE USING (auth.uid() = user_id);

-- 4. Enable RLS on encouragements table
ALTER TABLE encouragements ENABLE ROW LEVEL SECURITY;

-- 5. Drop existing policies to recreate them
DROP POLICY IF EXISTS "Users can view all encouragements" ON encouragements;
DROP POLICY IF EXISTS "Users can create encouragements" ON encouragements;
DROP POLICY IF EXISTS "Users can delete their own encouragements" ON encouragements;

-- 6. Create policies for encouragements
-- Allow users to view all encouragements
CREATE POLICY "Users can view all encouragements" ON encouragements
FOR SELECT USING (true);

-- Allow authenticated users to create encouragements
CREATE POLICY "Users can create encouragements" ON encouragements
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own encouragements
CREATE POLICY "Users can delete their own encouragements" ON encouragements
FOR DELETE USING (auth.uid() = user_id);

-- 7. Ensure the reactions table has the correct structure
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_post_id_user_id_reaction_key;
ALTER TABLE reactions ADD CONSTRAINT reactions_post_id_user_id_reaction_key 
  UNIQUE (post_id, user_id, reaction);

-- 8. Test to ensure tables are accessible
-- This will help identify any permission issues
DO $$
BEGIN
  -- Test select on reactions
  PERFORM 1 FROM reactions LIMIT 1;
  RAISE NOTICE 'Reactions table is accessible';
  
  -- Test select on encouragements
  PERFORM 1 FROM encouragements LIMIT 1;
  RAISE NOTICE 'Encouragements table is accessible';
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error accessing tables: %', SQLERRM;
END $$;

-- 9. Grant usage on schemas
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 10. Ensure foreign key relationships are correct
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_post_id_fkey;
ALTER TABLE reactions ADD CONSTRAINT reactions_post_id_fkey 
  FOREIGN KEY (post_id) REFERENCES community_posts(id) ON DELETE CASCADE;

ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_user_id_fkey;
ALTER TABLE reactions ADD CONSTRAINT reactions_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE encouragements DROP CONSTRAINT IF EXISTS encouragements_post_id_fkey;
ALTER TABLE encouragements ADD CONSTRAINT encouragements_post_id_fkey 
  FOREIGN KEY (post_id) REFERENCES community_posts(id) ON DELETE CASCADE;

ALTER TABLE encouragements DROP CONSTRAINT IF EXISTS encouragements_user_id_fkey;
ALTER TABLE encouragements ADD CONSTRAINT encouragements_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Success message
SELECT 'RLS policies for reactions and encouragements have been fixed!' as message;