-- Create Reactions Table for Community Posts
-- Run this in Supabase SQL Editor to enable reactions persistence

-- Create reactions table if it doesn't exist
CREATE TABLE IF NOT EXISTS reactions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction VARCHAR(50) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Prevent duplicate reactions from same user on same post
  UNIQUE(post_id, user_id, reaction)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_reactions_post_id ON reactions(post_id);
CREATE INDEX IF NOT EXISTS idx_reactions_user_id ON reactions(user_id);

-- Enable RLS
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view all reactions" ON reactions;
DROP POLICY IF EXISTS "Users can add their own reactions" ON reactions;
DROP POLICY IF EXISTS "Users can remove their own reactions" ON reactions;

-- Create policies
CREATE POLICY "Users can view all reactions" ON reactions
  FOR SELECT USING (true);

CREATE POLICY "Users can add their own reactions" ON reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their own reactions" ON reactions
  FOR DELETE USING (auth.uid() = user_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE reactions;

-- Grant permissions
GRANT ALL ON reactions TO authenticated;

-- Test query to verify everything is working
SELECT 
  'Table exists' as check_item,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'reactions') as status
UNION ALL
SELECT 
  'RLS enabled' as check_item,
  relrowsecurity as status
FROM pg_class 
WHERE relname = 'reactions'
UNION ALL
SELECT 
  'Policies exist' as check_item,
  COUNT(*) > 0 as status
FROM pg_policies 
WHERE tablename = 'reactions';