-- Simple Private Messages Setup
-- This creates just the essential table and permissions for private messaging

-- 1. Create private_messages table if it doesn't exist
CREATE TABLE IF NOT EXISTS private_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_private_messages_from_user ON private_messages(from_user_id);
CREATE INDEX IF NOT EXISTS idx_private_messages_to_user ON private_messages(to_user_id);
CREATE INDEX IF NOT EXISTS idx_private_messages_created_at ON private_messages(created_at DESC);

-- 3. Enable RLS
ALTER TABLE private_messages ENABLE ROW LEVEL SECURITY;

-- 4. Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own messages" ON private_messages;
DROP POLICY IF EXISTS "Users can send messages" ON private_messages;
DROP POLICY IF EXISTS "Users can update read status" ON private_messages;
DROP POLICY IF EXISTS "Users can delete their sent messages" ON private_messages;

-- 5. Create simple RLS policies
CREATE POLICY "Users can view their own messages" ON private_messages
FOR SELECT USING (
  auth.uid() = from_user_id OR auth.uid() = to_user_id
);

CREATE POLICY "Users can send messages" ON private_messages
FOR INSERT WITH CHECK (
  auth.uid() = from_user_id
);

CREATE POLICY "Users can update read status" ON private_messages
FOR UPDATE USING (
  auth.uid() = to_user_id
) WITH CHECK (
  auth.uid() = to_user_id
);

CREATE POLICY "Users can delete their sent messages" ON private_messages
FOR DELETE USING (
  auth.uid() = from_user_id
);

-- 6. Grant permissions
GRANT ALL ON private_messages TO authenticated;

-- 7. Enable realtime
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'private_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_messages;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- If realtime publication doesn't exist, ignore the error
  NULL;
END $$;

-- Success message
SELECT 'Simple private messaging setup completed!' as message;