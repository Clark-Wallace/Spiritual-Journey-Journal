-- Fix the send_fellowship_request function to handle constraints properly

DROP FUNCTION IF EXISTS send_fellowship_request(UUID, UUID);

CREATE OR REPLACE FUNCTION send_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_request fellowship_requests;
  v_reverse_request fellowship_requests;
  v_existing_fellowship fellowships;
BEGIN
  -- Check if trying to send request to self
  IF p_from_user_id = p_to_user_id THEN
    RETURN jsonb_build_object(
      'success', false, 
      'message', 'Cannot send fellowship request to yourself'
    );
  END IF;

  -- Check if already in fellowship
  SELECT * INTO v_existing_fellowship
  FROM fellowships
  WHERE user_id = p_from_user_id AND fellow_id = p_to_user_id;
  
  IF v_existing_fellowship IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true, 
      'message', 'Already in fellowship'
    );
  END IF;
  
  -- Check for existing request from us to them
  SELECT * INTO v_existing_request
  FROM fellowship_requests
  WHERE from_user_id = p_from_user_id 
    AND to_user_id = p_to_user_id
    AND status = 'pending';
  
  IF v_existing_request IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true, 
      'message', 'Request already pending'
    );
  END IF;
  
  -- Check for reverse request (they requested us)
  SELECT * INTO v_reverse_request
  FROM fellowship_requests
  WHERE from_user_id = p_to_user_id 
    AND to_user_id = p_from_user_id
    AND status = 'pending';
  
  IF v_reverse_request IS NOT NULL THEN
    -- Auto-accept: update their request
    UPDATE fellowship_requests
    SET status = 'accepted', responded_at = NOW()
    WHERE id = v_reverse_request.id;
    
    -- Create mutual fellowship (skip if constraint fails)
    BEGIN
      INSERT INTO fellowships (user_id, fellow_id)
      VALUES 
        (p_from_user_id, p_to_user_id),
        (p_to_user_id, p_from_user_id)
      ON CONFLICT DO NOTHING;
    EXCEPTION WHEN check_violation THEN
      -- If constraint fails, just continue
      NULL;
    END;
    
    RETURN jsonb_build_object(
      'success', true, 
      'message', 'Fellowship established (mutual request)'
    );
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
  VALUES (p_from_user_id, p_to_user_id, 'pending')
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING;
  
  RETURN jsonb_build_object(
    'success', true, 
    'message', 'Fellowship request sent'
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'message', 'Error: ' || SQLERRM
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION send_fellowship_request(UUID, UUID) TO authenticated;

-- Also update the accept function to handle constraints
DROP FUNCTION IF EXISTS accept_fellowship_request(UUID, UUID);

CREATE OR REPLACE FUNCTION accept_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_request RECORD;
BEGIN
  -- Get the request details
  SELECT * INTO v_request
  FROM fellowship_requests
  WHERE id = p_request_id
    AND to_user_id = p_user_id
    AND status = 'pending';
  
  IF v_request IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Request not found or already processed'
    );
  END IF;
  
  -- Don't allow accepting request from self
  IF v_request.from_user_id = v_request.to_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Cannot accept fellowship with yourself'
    );
  END IF;
  
  -- Update the request status
  UPDATE fellowship_requests
  SET status = 'accepted', responded_at = NOW()
  WHERE id = p_request_id;
  
  -- Create both sides of the fellowship (skip on constraint violation)
  BEGIN
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES 
      (v_request.from_user_id, v_request.to_user_id),
      (v_request.to_user_id, v_request.from_user_id)
    ON CONFLICT (user_id, fellow_id) DO NOTHING;
  EXCEPTION WHEN check_violation THEN
    -- If constraint fails (self-reference), just continue
    NULL;
  END;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fellowship request accepted'
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION accept_fellowship_request(UUID, UUID) TO authenticated;