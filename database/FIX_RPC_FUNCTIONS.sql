-- Fix RPC Functions with Ambiguous Column References
-- This addresses the column ambiguity issues

-- 1. Fix send_chat_request function
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
  -- Use fully qualified column names to avoid ambiguity
  SELECT cr.id INTO v_existing_request
  FROM chat_requests cr
  WHERE ((cr.from_user_id = p_from_user_id AND cr.to_user_id = p_to_user_id) 
         OR (cr.from_user_id = p_to_user_id AND cr.to_user_id = p_from_user_id))
    AND cr.status = 'pending'
    AND cr.expires_at > NOW();
  
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

-- 2. Fix get_conversation_messages function (if it exists)
CREATE OR REPLACE FUNCTION get_conversation_messages(
  p_user_id UUID,
  p_other_user_id UUID,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
  message_id UUID,
  from_user_id UUID,
  from_user_name TEXT,
  to_user_id UUID,
  to_user_name TEXT,
  message TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  is_mine BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Mark messages as read for the requesting user
  UPDATE private_messages pm
  SET is_read = true
  WHERE pm.to_user_id = p_user_id 
    AND pm.from_user_id = p_other_user_id 
    AND pm.is_read = false;
  
  -- Return conversation messages with fully qualified column names
  RETURN QUERY
  SELECT 
    pm.id as message_id,
    pm.from_user_id,
    CASE 
      WHEN pm.from_user_id = p_user_id THEN 'You'
      ELSE 'User'
    END as from_user_name,
    pm.to_user_id,
    CASE 
      WHEN pm.to_user_id = p_user_id THEN 'You'
      ELSE 'User'
    END as to_user_name,
    pm.message,
    pm.is_read,
    pm.created_at,
    (pm.from_user_id = p_user_id) as is_mine
  FROM private_messages pm
  WHERE (pm.from_user_id = p_user_id AND pm.to_user_id = p_other_user_id)
     OR (pm.from_user_id = p_other_user_id AND pm.to_user_id = p_user_id)
  ORDER BY pm.created_at ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- 3. Grant permissions
GRANT EXECUTE ON FUNCTION send_chat_request(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_conversation_messages(UUID, UUID, INTEGER, INTEGER) TO authenticated;

-- Success message
SELECT 'RPC functions fixed for column ambiguity issues!' as message;