-- Safe Chat Request System Migration
-- This handles existing policies and functions gracefully

-- 1. Create chat_requests table (if not exists)
CREATE TABLE IF NOT EXISTS chat_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  from_user_name TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'timeout')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 seconds')
);

-- 2. Create indexes for performance (if not exists)
CREATE INDEX IF NOT EXISTS idx_chat_requests_to_user ON chat_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_chat_requests_from_user ON chat_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_chat_requests_status ON chat_requests(status);
CREATE INDEX IF NOT EXISTS idx_chat_requests_expires_at ON chat_requests(expires_at);

-- 3. Enable RLS
ALTER TABLE chat_requests ENABLE ROW LEVEL SECURITY;

-- 4. Drop existing policies if they exist and recreate them
DO $$ 
BEGIN
  -- Drop existing policies
  DROP POLICY IF EXISTS "Users can view their chat requests" ON chat_requests;
  DROP POLICY IF EXISTS "Users can send chat requests" ON chat_requests;
  DROP POLICY IF EXISTS "Recipients can respond to requests" ON chat_requests;
  DROP POLICY IF EXISTS "Users can cancel their requests" ON chat_requests;
  
  -- Create policies
  CREATE POLICY "Users can view their chat requests" ON chat_requests
  FOR SELECT USING (
    auth.uid() = from_user_id OR auth.uid() = to_user_id
  );

  CREATE POLICY "Users can send chat requests" ON chat_requests
  FOR INSERT WITH CHECK (
    auth.uid() = from_user_id
  );

  CREATE POLICY "Recipients can respond to requests" ON chat_requests
  FOR UPDATE USING (
    auth.uid() = to_user_id
  ) WITH CHECK (
    auth.uid() = to_user_id
  );

  CREATE POLICY "Users can cancel their requests" ON chat_requests
  FOR DELETE USING (
    auth.uid() = from_user_id
  );
END $$;

-- 5. Drop and recreate functions to ensure they're up to date
DROP FUNCTION IF EXISTS cleanup_expired_chat_requests();
DROP FUNCTION IF EXISTS get_pending_chat_requests(UUID);
DROP FUNCTION IF EXISTS send_chat_request(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS respond_to_chat_request(UUID, UUID, TEXT);

-- Function to clean up expired requests
CREATE OR REPLACE FUNCTION cleanup_expired_chat_requests()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE chat_requests 
  SET status = 'timeout', responded_at = NOW()
  WHERE status = 'pending' 
    AND expires_at < NOW();
END;
$$;

-- Function to get pending requests for a user
CREATE OR REPLACE FUNCTION get_pending_chat_requests(p_user_id UUID)
RETURNS TABLE(
  request_id UUID,
  from_user_id UUID,
  from_user_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Clean up expired requests first
  PERFORM cleanup_expired_chat_requests();
  
  -- Return active pending requests
  RETURN QUERY
  SELECT 
    cr.id as request_id,
    cr.from_user_id,
    cr.from_user_name,
    cr.created_at,
    cr.expires_at
  FROM chat_requests cr
  WHERE cr.to_user_id = p_user_id
    AND cr.status = 'pending'
    AND cr.expires_at > NOW()
  ORDER BY cr.created_at DESC;
END;
$$;

-- Function to send a chat request
CREATE OR REPLACE FUNCTION send_chat_request(
  p_from_user_id UUID,
  p_to_user_id UUID,
  p_from_user_name TEXT
)
RETURNS TABLE(
  request_id UUID,
  status TEXT,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_request UUID;
  v_new_request_id UUID;
BEGIN
  -- Clean up expired requests first
  PERFORM cleanup_expired_chat_requests();
  
  -- Check if there's already a pending request between these users
  SELECT id INTO v_existing_request
  FROM chat_requests 
  WHERE ((from_user_id = p_from_user_id AND to_user_id = p_to_user_id) 
         OR (from_user_id = p_to_user_id AND to_user_id = p_from_user_id))
    AND status = 'pending'
    AND expires_at > NOW();
  
  IF v_existing_request IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_request, 'exists'::TEXT, 'Chat request already pending'::TEXT;
    RETURN;
  END IF;
  
  -- Create new request
  INSERT INTO chat_requests (from_user_id, to_user_id, from_user_name)
  VALUES (p_from_user_id, p_to_user_id, p_from_user_name)
  RETURNING id INTO v_new_request_id;
  
  RETURN QUERY SELECT v_new_request_id, 'sent'::TEXT, 'Chat request sent'::TEXT;
END;
$$;

-- Function to respond to a chat request
CREATE OR REPLACE FUNCTION respond_to_chat_request(
  p_request_id UUID,
  p_user_id UUID,
  p_response TEXT -- 'accepted' or 'declined'
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  from_user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_from_user_id UUID;
  v_to_user_id UUID;
  v_current_status TEXT;
BEGIN
  -- Get request details
  SELECT cr.from_user_id, cr.to_user_id, cr.status
  INTO v_from_user_id, v_to_user_id, v_current_status
  FROM chat_requests cr
  WHERE cr.id = p_request_id;
  
  -- Validate request exists and user can respond
  IF v_from_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Request not found'::TEXT, NULL::UUID;
    RETURN;
  END IF;
  
  IF v_to_user_id != p_user_id THEN
    RETURN QUERY SELECT FALSE, 'Not authorized'::TEXT, NULL::UUID;
    RETURN;
  END IF;
  
  IF v_current_status != 'pending' THEN
    RETURN QUERY SELECT FALSE, 'Request no longer pending'::TEXT, NULL::UUID;
    RETURN;
  END IF;
  
  -- Update request status
  UPDATE chat_requests 
  SET status = p_response, responded_at = NOW()
  WHERE id = p_request_id;
  
  RETURN QUERY SELECT TRUE, ('Request ' || p_response)::TEXT, v_from_user_id;
END;
$$;

-- 6. Grant permissions
GRANT ALL ON chat_requests TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_expired_chat_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION get_pending_chat_requests(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION send_chat_request(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION respond_to_chat_request(UUID, UUID, TEXT) TO authenticated;

-- 7. Enable realtime (safely)
DO $$ 
BEGIN
  -- Remove from publication if it exists, then add it
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE chat_requests;
  EXCEPTION WHEN OTHERS THEN
    -- Ignore error if table wasn't in publication
    NULL;
  END;
  
  -- Add to publication
  ALTER PUBLICATION supabase_realtime ADD TABLE chat_requests;
EXCEPTION WHEN OTHERS THEN
  -- If realtime publication doesn't exist, ignore the error
  NULL;
END $$;

-- Success message
SELECT 'Chat request system created/updated successfully!' as message;