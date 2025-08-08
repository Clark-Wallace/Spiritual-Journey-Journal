-- Fix Reactions Table (handles existing table)
-- Run this in Supabase SQL Editor

-- First check if the table exists and what columns it has
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'reactions';

-- If the table exists but has wrong columns, we need to fix it
-- Check if reaction column exists, if not add it
ALTER TABLE reactions 
ADD COLUMN IF NOT EXISTS reaction VARCHAR(50);

-- If reaction_type exists and reaction doesn't, rename it
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'reactions' AND column_name = 'reaction_type'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'reactions' AND column_name = 'reaction'
  ) THEN
    ALTER TABLE reactions RENAME COLUMN reaction_type TO reaction;
  END IF;
END $$;

-- Ensure proper constraints
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_post_id_user_id_reaction_key;
ALTER TABLE reactions ADD CONSTRAINT reactions_post_id_user_id_reaction_key 
  UNIQUE(post_id, user_id, reaction);

-- Ensure RLS is enabled
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure they're correct
DROP POLICY IF EXISTS "Users can view all reactions" ON reactions;
DROP POLICY IF EXISTS "Users can add their own reactions" ON reactions;
DROP POLICY IF EXISTS "Users can remove their own reactions" ON reactions;

CREATE POLICY "Users can view all reactions" ON reactions
  FOR SELECT USING (true);

CREATE POLICY "Users can add their own reactions" ON reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their own reactions" ON reactions
  FOR DELETE USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON reactions TO authenticated;

-- Test the table structure
SELECT 
  c.column_name,
  c.data_type,
  c.is_nullable
FROM information_schema.columns c
WHERE c.table_name = 'reactions'
ORDER BY c.ordinal_position;

-- Test adding a reaction (will be rolled back)
BEGIN;
INSERT INTO reactions (post_id, user_id, reaction) 
VALUES (
  (SELECT id FROM community_posts LIMIT 1),
  auth.uid(),
  'test'
);
-- Check if it worked
SELECT * FROM reactions WHERE reaction = 'test';
-- Roll back the test
ROLLBACK;