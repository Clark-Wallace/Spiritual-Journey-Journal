-- Create encouragements table if it doesn't exist
CREATE TABLE IF NOT EXISTS encouragements (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE encouragements ENABLE ROW LEVEL SECURITY;

-- Policies for encouragements
CREATE POLICY "Anyone can view encouragements"
  ON encouragements FOR SELECT
  USING (true);

CREATE POLICY "Authenticated users can create encouragements"
  ON encouragements FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own encouragements"
  ON encouragements FOR DELETE
  USING (auth.uid() = user_id);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_encouragements_post_id ON encouragements(post_id);
CREATE INDEX IF NOT EXISTS idx_encouragements_created_at ON encouragements(created_at DESC);