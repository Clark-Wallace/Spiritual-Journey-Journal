-- Fix the remove_fellowship function to also clean up old requests

DROP FUNCTION IF EXISTS remove_fellowship(UUID, UUID);

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
  
  -- Clean up ALL related requests (not just accepted ones)
  -- This allows users to send new requests after unfellowshipping
  DELETE FROM fellowship_requests
  WHERE (from_user_id = p_user_id AND to_user_id = p_fellow_id)
     OR (from_user_id = p_fellow_id AND to_user_id = p_user_id);
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Fellowship and all requests removed'
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION remove_fellowship(UUID, UUID) TO authenticated;

-- Clean up existing orphaned requests between Clark AI and Clark Wallace
DELETE FROM fellowship_requests
WHERE (from_user_id = 'a43ff393-dde1-4001-b667-23f518e72499' AND to_user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
   OR (from_user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c' AND to_user_id = 'a43ff393-dde1-4001-b667-23f518e72499');

-- Verify cleanup
SELECT 
  fr.id,
  from_profile.display_name as from_name,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE from_user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
   OR to_user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');