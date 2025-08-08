-- Fix the get_fellowship_requests function to properly return requests

DROP FUNCTION IF EXISTS get_fellowship_requests(UUID);

CREATE OR REPLACE FUNCTION get_fellowship_requests(p_user_id UUID)
RETURNS TABLE(
  request_id UUID,
  from_user_id UUID,
  from_user_name TEXT,
  to_user_id UUID,
  to_user_name TEXT,
  status VARCHAR(20),
  created_at TIMESTAMPTZ,
  direction TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    fr.id as request_id,
    fr.from_user_id,
    COALESCE(from_profile.display_name, 'Unknown') as from_user_name,
    fr.to_user_id,
    COALESCE(to_profile.display_name, 'Unknown') as to_user_name,
    fr.status,
    fr.created_at,
    CASE 
      WHEN fr.from_user_id = p_user_id THEN 'sent'::text
      WHEN fr.to_user_id = p_user_id THEN 'received'::text
      ELSE 'unknown'::text
    END as direction
  FROM fellowship_requests fr
  LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
  LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
  WHERE (fr.from_user_id = p_user_id OR fr.to_user_id = p_user_id)
    AND fr.status = 'pending'
    AND fr.from_user_id != fr.to_user_id  -- Exclude self-requests
  ORDER BY fr.created_at DESC;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_fellowship_requests(UUID) TO authenticated;

-- Test the function to make sure it works
-- SELECT * FROM get_fellowship_requests('your-user-id-here');

-- Also let's clean up any self-requests that might exist
DELETE FROM fellowship_requests 
WHERE from_user_id = to_user_id;

-- And prevent them in the future with a constraint
ALTER TABLE fellowship_requests
DROP CONSTRAINT IF EXISTS no_self_requests;

ALTER TABLE fellowship_requests
ADD CONSTRAINT no_self_requests
CHECK (from_user_id != to_user_id);