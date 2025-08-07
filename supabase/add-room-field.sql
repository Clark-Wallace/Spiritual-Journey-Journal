-- Add room field to chat_messages table for multiple chat rooms

-- Add the room column if it doesn't exist
ALTER TABLE chat_messages 
ADD COLUMN IF NOT EXISTS room VARCHAR(50) DEFAULT 'fellowship';

-- Create an index for better query performance
CREATE INDEX IF NOT EXISTS idx_chat_messages_room ON chat_messages(room);

-- Update RLS policy to include room filtering
DROP POLICY IF EXISTS "Users can view chat messages" ON chat_messages;
CREATE POLICY "Users can view chat messages" ON chat_messages
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert chat messages" ON chat_messages;
CREATE POLICY "Users can insert chat messages" ON chat_messages
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own messages" ON chat_messages;
CREATE POLICY "Users can delete own messages" ON chat_messages
  FOR DELETE USING (auth.uid() = user_id);