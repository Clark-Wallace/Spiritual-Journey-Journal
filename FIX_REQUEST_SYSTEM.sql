-- Fix Fellowship Request System - Run this in Supabase SQL Editor

-- 1. Fix upsert_user_profile permissions (remove SECURITY INVOKER)
DROP FUNCTION IF EXISTS upsert_user_profile(UUID, TEXT);

CREATE OR REPLACE FUNCTION upsert_user_profile(
  p_user_id UUID,
  p_display_name TEXT
)
RETURNS void AS $$
BEGIN
  INSERT INTO user_profiles (user_id, display_name)
  VALUES (p_user_id, p_display_name)
  ON CONFLICT (user_id)
  DO UPDATE SET 
    display_name = EXCLUDED.display_name,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_user_profile TO anon;
GRANT ALL ON user_profiles TO authenticated;
GRANT ALL ON user_profiles TO anon;

-- 2. Fix send_fellowship_request to not fallback to direct add
DROP FUNCTION IF EXISTS send_fellowship_request(UUID, UUID);

CREATE OR REPLACE FUNCTION send_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON AS $$
DECLARE
  v_existing_fellowship BOOLEAN;
  v_existing_request RECORD;
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
  WHERE ((from_user_id = p_from_user_id AND to_user_id = p_to_user_id)
     OR (from_user_id = p_to_user_id AND to_user_id = p_from_user_id))
    AND status = 'pending'
  LIMIT 1;
  
  IF v_existing_request.id IS NOT NULL THEN
    IF v_existing_request.from_user_id = p_to_user_id THEN
      -- They already requested you, auto-accept both directions
      UPDATE fellowship_requests
      SET status = 'accepted', responded_at = NOW()
      WHERE id = v_existing_request.id;
      
      -- Create mutual fellowship
      INSERT INTO fellowships (user_id, fellow_id)
      VALUES 
        (p_from_user_id, p_to_user_id),
        (p_to_user_id, p_from_user_id)
      ON CONFLICT DO NOTHING;
      
      RETURN json_build_object('success', true, 'message', 'Fellowship established (mutual request)');
    ELSE
      -- Request already exists from you
      RETURN json_build_object('success', false, 'message', 'Request already pending');
    END IF;
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
  VALUES (p_from_user_id, p_to_user_id, 'pending');
  
  RETURN json_build_object('success', true, 'message', 'Request sent');
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated;

-- 3. Verify fellowship_requests table structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'fellowship_requests'
ORDER BY ordinal_position;

-- 4. Test the function manually (replace with actual user IDs)
-- SELECT send_fellowship_request('user_id_1'::uuid, 'user_id_2'::uuid);

-- 5. Check current fellowship requests
SELECT 
  fr.id,
  fr.from_user_id,
  fp.display_name as from_name,
  fr.to_user_id,
  tp.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles fp ON fp.user_id = fr.from_user_id
LEFT JOIN user_profiles tp ON tp.user_id = fr.to_user_id
ORDER BY fr.created_at DESC;

-- 6. Display status
SELECT 
  'Request system fixed!' as status,
  (SELECT COUNT(*) FROM fellowship_requests WHERE status = 'pending') as pending_requests,
  (SELECT COUNT(*) FROM fellowships) as total_fellowships;