-- Fix the accept_fellowship_request RPC function to work with RLS policies

-- Drop the existing function
DROP FUNCTION IF EXISTS accept_fellowship_request(uuid, uuid);

-- Create a new version that uses SECURITY DEFINER to bypass RLS
CREATE OR REPLACE FUNCTION accept_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSONB
SECURITY DEFINER -- This allows the function to bypass RLS
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_request RECORD;
  v_result JSONB;
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
  
  -- Update the request status
  UPDATE fellowship_requests
  SET status = 'accepted',
      responded_at = NOW()
  WHERE id = p_request_id;
  
  -- Create both sides of the fellowship
  -- Since this function uses SECURITY DEFINER, it can bypass RLS
  INSERT INTO fellowships (user_id, fellow_id)
  VALUES 
    (v_request.from_user_id, v_request.to_user_id),
    (v_request.to_user_id, v_request.from_user_id)
  ON CONFLICT (user_id, fellow_id) DO NOTHING;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fellowship request accepted'
  );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION accept_fellowship_request(UUID, UUID) TO authenticated;

-- Also fix the decline function while we're at it
DROP FUNCTION IF EXISTS decline_fellowship_request(uuid, uuid);

CREATE OR REPLACE FUNCTION decline_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update the request status
  UPDATE fellowship_requests
  SET status = 'declined',
      responded_at = NOW()
  WHERE id = p_request_id
    AND to_user_id = p_user_id
    AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Request not found or already processed'
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fellowship request declined'
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION decline_fellowship_request(UUID, UUID) TO authenticated;

-- Verify the functions exist
SELECT proname, prosecdef 
FROM pg_proc 
WHERE proname IN ('accept_fellowship_request', 'decline_fellowship_request');