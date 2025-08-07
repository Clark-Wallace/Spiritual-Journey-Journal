-- The Way - Chat Room Schema

-- Chat messages table
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_name VARCHAR(255),
  message TEXT NOT NULL,
  scripture_reference VARCHAR(100),
  is_announcement BOOLEAN DEFAULT false,
  is_prayer_request BOOLEAN DEFAULT false,
  edited_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- User presence/online status
CREATE TABLE IF NOT EXISTS user_presence (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  user_name VARCHAR(255),
  status VARCHAR(20) DEFAULT 'online' CHECK (status IN ('online', 'away', 'praying', 'reading')),
  last_seen TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Message reactions (for chat)
CREATE TABLE IF NOT EXISTS chat_reactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  reaction VARCHAR(20) CHECK (reaction IN ('amen', 'pray', 'love', 'hallelujah', 'praise')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE(message_id, user_id, reaction)
);

-- Create indexes
CREATE INDEX idx_chat_messages_created ON chat_messages(created_at DESC);
CREATE INDEX idx_chat_messages_user ON chat_messages(user_id);
CREATE INDEX idx_user_presence_last_seen ON user_presence(last_seen DESC);

-- Enable RLS
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_reactions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for chat_messages
CREATE POLICY "Anyone can view chat messages" ON chat_messages
  FOR SELECT USING (true);

CREATE POLICY "Authenticated users can send messages" ON chat_messages
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can edit own messages" ON chat_messages
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own messages" ON chat_messages
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for user_presence
CREATE POLICY "Anyone can view presence" ON user_presence
  FOR SELECT USING (true);

CREATE POLICY "Users can update own presence" ON user_presence
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own presence status" ON user_presence
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own presence" ON user_presence
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for chat_reactions
CREATE POLICY "Anyone can view reactions" ON chat_reactions
  FOR SELECT USING (true);

CREATE POLICY "Users can add reactions" ON chat_reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove own reactions" ON chat_reactions
  FOR DELETE USING (auth.uid() = user_id);

-- Function to clean up old messages (optional, keeps last 1000 messages)
CREATE OR REPLACE FUNCTION cleanup_old_messages()
RETURNS void AS $$
BEGIN
  DELETE FROM chat_messages
  WHERE id NOT IN (
    SELECT id FROM chat_messages
    ORDER BY created_at DESC
    LIMIT 1000
  );
END;
$$ LANGUAGE plpgsql;