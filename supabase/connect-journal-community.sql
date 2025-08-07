-- Add connection between journal entries and community posts
ALTER TABLE community_posts 
ADD COLUMN journal_entry_id UUID REFERENCES journal_entries(id) ON DELETE SET NULL,
ADD COLUMN source_type VARCHAR(20) DEFAULT 'direct' CHECK (source_type IN ('journal', 'direct'));

-- Add index for performance
CREATE INDEX idx_community_posts_journal_entry_id ON community_posts(journal_entry_id);
CREATE INDEX idx_community_posts_user_id ON community_posts(user_id);
CREATE INDEX idx_community_posts_source_type ON community_posts(source_type);

-- Create view for user's shared content
CREATE OR REPLACE VIEW user_shared_content AS
SELECT 
  cp.*,
  je.date as journal_date,
  je.mood as journal_mood,
  je.content as journal_content,
  COUNT(DISTINCT r.id) as reaction_count,
  COUNT(DISTINCT e.id) as comment_count
FROM community_posts cp
LEFT JOIN journal_entries je ON cp.journal_entry_id = je.id
LEFT JOIN reactions r ON cp.id = r.post_id
LEFT JOIN encouragements e ON cp.id = e.post_id
WHERE cp.source_type = 'journal'
GROUP BY cp.id, je.id;

-- Update RLS policies for the view
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;

-- Policy to allow users to see their own posts easily
CREATE POLICY "Users can see their own posts"
  ON community_posts FOR SELECT
  USING (auth.uid() = user_id OR true); -- Shows all posts but identifies own

-- Add a function to sync journal updates to community posts
CREATE OR REPLACE FUNCTION sync_journal_to_community(
  p_journal_entry_id UUID,
  p_content TEXT,
  p_mood VARCHAR(50)
) RETURNS void AS $$
BEGIN
  UPDATE community_posts
  SET 
    content = p_content,
    mood = p_mood,
    updated_at = NOW()
  WHERE journal_entry_id = p_journal_entry_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;