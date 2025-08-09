-- Create a function to properly remove fellowship from both sides

CREATE OR REPLACE FUNCTION remove_fellowship(
  p_user_id UUID,
  p_fellow_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Remove both sides of the fellowship
  DELETE FROM fellowships 
  WHERE (user_id = p_user_id AND fellow_id = p_fellow_id)
     OR (user_id = p_fellow_id AND fellow_id = p_user_id);
  
  -- Also clean up any related pending requests
  UPDATE fellowship_requests
  SET status = 'cancelled'
  WHERE status = 'accepted'
    AND ((from_user_id = p_user_id AND to_user_id = p_fellow_id)
      OR (from_user_id = p_fellow_id AND to_user_id = p_user_id));
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fellowship removed'
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION remove_fellowship(UUID, UUID) TO authenticated;

-- Test removing fellowship between Clark AI and Clark Wallace
-- SELECT remove_fellowship('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');