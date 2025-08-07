-- Add room tracking to user presence

-- Add current_room column to user_presence table
ALTER TABLE user_presence 
ADD COLUMN IF NOT EXISTS current_room VARCHAR(50) DEFAULT 'fellowship';

-- Create index for room-based queries
CREATE INDEX IF NOT EXISTS idx_user_presence_room ON user_presence(current_room);

-- Update RLS policies for presence
DROP POLICY IF EXISTS "Users can view presence" ON user_presence;
CREATE POLICY "Users can view presence" ON user_presence
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own presence" ON user_presence;
CREATE POLICY "Users can update own presence" ON user_presence
  FOR ALL USING (auth.uid() = user_id);