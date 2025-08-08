-- Create Fellowship Requests System
-- Run this in Supabase SQL Editor

-- 1. Create fellowship_requests table
CREATE TABLE IF NOT EXISTS fellowship_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(from_user_id, to_user_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_from_user ON fellowship_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_to_user ON fellowship_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_status ON fellowship_requests(status);

-- Enable RLS
ALTER TABLE fellowship_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can send requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update received requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can cancel sent requests" ON fellowship_requests;

-- Create policies
CREATE POLICY "Users can view own requests" ON fellowship_requests
  FOR SELECT USING (
    auth.uid() = from_user_id OR 
    auth.uid() = to_user_id
  );

CREATE POLICY "Users can send requests" ON fellowship_requests
  FOR INSERT WITH CHECK (
    auth.uid() = from_user_id AND
    from_user_id != to_user_id -- Can't request yourself
  );

CREATE POLICY "Users can update received requests" ON fellowship_requests
  FOR UPDATE USING (
    auth.uid() = to_user_id AND
    status = 'pending'
  );

CREATE POLICY "Users can cancel sent requests" ON fellowship_requests
  FOR UPDATE USING (
    auth.uid() = from_user_id AND
    status = 'pending'
  );

-- Grant permissions
GRANT ALL ON fellowship_requests TO authenticated;

-- 2. Function to send fellowship request
CREATE OR REPLACE FUNCTION send_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_existing_fellowship BOOLEAN;
  v_existing_request RECORD;
  v_result JSON;
BEGIN
  -- Check if fellowship already exists
  SELECT EXISTS(
    SELECT 1 FROM fellowships 
    WHERE user_id = p_from_user_id AND fellow_id = p_to_user_id
  ) INTO v_existing_fellowship;
  
  IF v_existing_fellowship THEN
    RETURN json_build_object('success', false, 'message', 'Already in fellowship');
  END IF;
  
  -- Check for existing request
  SELECT * INTO v_existing_request
  FROM fellowship_requests
  WHERE (from_user_id = p_from_user_id AND to_user_id = p_to_user_id)
     OR (from_user_id = p_to_user_id AND to_user_id = p_from_user_id)
  LIMIT 1;
  
  IF v_existing_request.id IS NOT NULL THEN
    IF v_existing_request.status = 'pending' THEN
      IF v_existing_request.from_user_id = p_to_user_id THEN
        -- They already requested you, auto-accept
        PERFORM accept_fellowship_request(v_existing_request.id, p_from_user_id);
        RETURN json_build_object('success', true, 'message', 'Fellowship established (mutual request)');
      ELSE
        RETURN json_build_object('success', false, 'message', 'Request already pending');
      END IF;
    ELSE
      -- Update existing declined/cancelled request to pending
      UPDATE fellowship_requests
      SET status = 'pending', 
          created_at = NOW(),
          responded_at = NULL,
          from_user_id = p_from_user_id,
          to_user_id = p_to_user_id
      WHERE id = v_existing_request.id;
      RETURN json_build_object('success', true, 'message', 'Request sent');
    END IF;
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id)
  VALUES (p_from_user_id, p_to_user_id);
  
  RETURN json_build_object('success', true, 'message', 'Request sent');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Function to accept fellowship request
CREATE OR REPLACE FUNCTION accept_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_request RECORD;
BEGIN
  -- Get the request
  SELECT * INTO v_request
  FROM fellowship_requests
  WHERE id = p_request_id AND to_user_id = p_user_id AND status = 'pending';
  
  IF v_request.id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Request not found or already processed');
  END IF;
  
  -- Update request status
  UPDATE fellowship_requests
  SET status = 'accepted', responded_at = NOW()
  WHERE id = p_request_id;
  
  -- Create mutual fellowship
  INSERT INTO fellowships (user_id, fellow_id)
  VALUES 
    (v_request.from_user_id, v_request.to_user_id),
    (v_request.to_user_id, v_request.from_user_id)
  ON CONFLICT DO NOTHING;
  
  RETURN json_build_object('success', true, 'message', 'Fellowship accepted');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Function to decline fellowship request
CREATE OR REPLACE FUNCTION decline_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSON AS $$
BEGIN
  UPDATE fellowship_requests
  SET status = 'declined', responded_at = NOW()
  WHERE id = p_request_id AND to_user_id = p_user_id AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Request not found');
  END IF;
  
  RETURN json_build_object('success', true, 'message', 'Request declined');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Function to cancel fellowship request
CREATE OR REPLACE FUNCTION cancel_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON AS $$
BEGIN
  UPDATE fellowship_requests
  SET status = 'cancelled', responded_at = NOW()
  WHERE from_user_id = p_from_user_id 
    AND to_user_id = p_to_user_id 
    AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'No pending request found');
  END IF;
  
  RETURN json_build_object('success', true, 'message', 'Request cancelled');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Function to get fellowship requests with user info
CREATE OR REPLACE FUNCTION get_fellowship_requests(p_user_id UUID)
RETURNS TABLE(
  request_id UUID,
  from_user_id UUID,
  from_user_name TEXT,
  to_user_id UUID,
  to_user_name TEXT,
  status TEXT,
  direction TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fr.id as request_id,
    fr.from_user_id,
    COALESCE(up_from.display_name, au_from.email::TEXT, 'Unknown') as from_user_name,
    fr.to_user_id,
    COALESCE(up_to.display_name, au_to.email::TEXT, 'Unknown') as to_user_name,
    fr.status,
    CASE 
      WHEN fr.from_user_id = p_user_id THEN 'sent'
      ELSE 'received'
    END as direction,
    fr.created_at
  FROM fellowship_requests fr
  LEFT JOIN user_profiles up_from ON up_from.user_id = fr.from_user_id
  LEFT JOIN user_profiles up_to ON up_to.user_id = fr.to_user_id
  LEFT JOIN auth.users au_from ON au_from.id = fr.from_user_id
  LEFT JOIN auth.users au_to ON au_to.id = fr.to_user_id
  WHERE (fr.from_user_id = p_user_id OR fr.to_user_id = p_user_id)
    AND fr.status = 'pending'
  ORDER BY fr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Function to check fellowship or request status
CREATE OR REPLACE FUNCTION check_fellowship_status(
  p_user_id UUID,
  p_other_user_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_is_fellow BOOLEAN;
  v_request RECORD;
BEGIN
  -- Check if already fellows
  SELECT EXISTS(
    SELECT 1 FROM fellowships 
    WHERE user_id = p_user_id AND fellow_id = p_other_user_id
  ) INTO v_is_fellow;
  
  IF v_is_fellow THEN
    RETURN json_build_object(
      'status', 'fellowship',
      'can_request', false
    );
  END IF;
  
  -- Check for pending request
  SELECT * INTO v_request
  FROM fellowship_requests
  WHERE ((from_user_id = p_user_id AND to_user_id = p_other_user_id)
     OR (from_user_id = p_other_user_id AND to_user_id = p_user_id))
    AND status = 'pending'
  LIMIT 1;
  
  IF v_request.id IS NOT NULL THEN
    IF v_request.from_user_id = p_user_id THEN
      RETURN json_build_object(
        'status', 'pending_sent',
        'request_id', v_request.id,
        'can_cancel', true
      );
    ELSE
      RETURN json_build_object(
        'status', 'pending_received',
        'request_id', v_request.id,
        'can_accept', true
      );
    END IF;
  END IF;
  
  -- No fellowship or request
  RETURN json_build_object(
    'status', 'none',
    'can_request', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION accept_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION decline_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_requests TO authenticated;
GRANT EXECUTE ON FUNCTION check_fellowship_status TO authenticated;

-- 8. Clean up old declined/cancelled requests (optional scheduled job)
CREATE OR REPLACE FUNCTION cleanup_old_fellowship_requests()
RETURNS void AS $$
BEGIN
  DELETE FROM fellowship_requests
  WHERE status IN ('declined', 'cancelled')
    AND responded_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- Display completion message
SELECT 'Fellowship request system created successfully!' as status;