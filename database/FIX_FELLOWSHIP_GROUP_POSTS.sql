-- Fix Fellowship Group Posts permissions and policies

-- First, ensure the table exists with correct structure
CREATE TABLE IF NOT EXISTS fellowship_group_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES fellowship_groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name VARCHAR(255),
  content TEXT NOT NULL,
  post_type VARCHAR(50) DEFAULT 'general',
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE fellowship_group_posts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate them
DROP POLICY IF EXISTS "Members can view group posts" ON fellowship_group_posts;
DROP POLICY IF EXISTS "Members can create posts" ON fellowship_group_posts;
DROP POLICY IF EXISTS "Users can update their own posts" ON fellowship_group_posts;
DROP POLICY IF EXISTS "Users can delete their own posts or admins can delete any" ON fellowship_group_posts;

-- Recreate policies with simpler logic

-- View policy - members can see posts in their groups
CREATE POLICY "Members can view group posts"
  ON fellowship_group_posts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
  );

-- Insert policy - members can create posts
CREATE POLICY "Members can create posts"
  ON fellowship_group_posts FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND is_active = true
    )
  );

-- Update policy - users can edit their own posts
CREATE POLICY "Users can update their own posts"
  ON fellowship_group_posts FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Delete policy - users can delete their own posts, admins/moderators can delete any
CREATE POLICY "Users can delete posts"
  ON fellowship_group_posts FOR DELETE
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM fellowship_group_members 
      WHERE group_id = fellowship_group_posts.group_id 
      AND user_id = auth.uid() 
      AND role IN ('admin', 'moderator')
      AND is_active = true
    )
  );

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_fellowship_group_posts_group_id 
  ON fellowship_group_posts(group_id);

CREATE INDEX IF NOT EXISTS idx_fellowship_group_posts_user_id 
  ON fellowship_group_posts(user_id);

CREATE INDEX IF NOT EXISTS idx_fellowship_group_posts_created_at 
  ON fellowship_group_posts(created_at DESC);

-- Enable realtime (correct syntax without IF NOT EXISTS)
ALTER PUBLICATION supabase_realtime ADD TABLE fellowship_group_posts;

-- Grant necessary permissions
GRANT ALL ON fellowship_group_posts TO authenticated;
GRANT ALL ON fellowship_group_posts TO service_role;

-- Also ensure fellowship_group_members has proper permissions
GRANT ALL ON fellowship_group_members TO authenticated;
GRANT ALL ON fellowship_groups TO authenticated;