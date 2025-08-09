-- Update send_fellowship_request to clean up old accepted/declined requests

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
  
  -- Clean up old accepted/declined/cancelled requests before checking
  DELETE FROM fellowship_requests
  WHERE from_user_id = p_from_user_id 
    AND to_user_id = p_to_user_id
    AND status IN ('accepted', 'declined', 'cancelled');
  
  -- Check for existing pending request from us to them
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
    
    -- Create mutual fellowship
    BEGIN
      INSERT INTO fellowships (user_id, fellow_id)
      VALUES 
        (p_from_user_id, p_to_user_id),
        (p_to_user_id, p_from_user_id)
      ON CONFLICT DO NOTHING;
    EXCEPTION WHEN check_violation THEN
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
  ON CONFLICT (from_user_id, to_user_id) 
  DO UPDATE SET 
    status = 'pending',
    created_at = NOW(),
    responded_at = NULL;
  
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