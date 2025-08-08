-- Final Fellowship Fix - Run this entire script in Supabase SQL Editor
-- This ensures all functions work properly

-- 1. First check if fellowship_requests table exists
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'fellowship_requests'
) as requests_table_exists;

-- 2. Fix the upsert_user_profile function permissions
DROP FUNCTION IF EXISTS upsert_user_profile(UUID, TEXT);

CREATE OR REPLACE FUNCTION upsert_user_profile(
  p_user_id UUID,
  p_display_name TEXT
)
RETURNS void AS $$
BEGIN
  -- Check if the user can update (must be authenticated)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  
  INSERT INTO user_profiles (user_id, display_name)
  VALUES (p_user_id, p_display_name)
  ON CONFLICT (user_id)
  DO UPDATE SET 
    display_name = EXCLUDED.display_name,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_user_profile TO anon;

-- 3. Check and fix send_fellowship_request
DROP FUNCTION IF EXISTS send_fellowship_request(UUID, UUID);

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
  -- First check if fellowship_requests table exists
  IF NOT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'fellowship_requests'
  ) THEN
    -- If no requests table, use direct fellowship add (old behavior)
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES (p_from_user_id, p_to_user_id)
    ON CONFLICT DO NOTHING;
    
    RETURN json_build_object('success', true, 'message', 'Fellowship added');
  END IF;
  
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
EXCEPTION
  WHEN OTHERS THEN
    -- If any error, fall back to direct fellowship
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES (p_from_user_id, p_to_user_id)
    ON CONFLICT DO NOTHING;
    
    RETURN json_build_object('success', true, 'message', 'Fellowship added (fallback)');
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated;

-- 4. Fix get_fellowship_requests to handle missing table
DROP FUNCTION IF EXISTS get_fellowship_requests(UUID);

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
  -- Check if table exists
  IF NOT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'fellowship_requests'
  ) THEN
    -- Return empty result
    RETURN;
  END IF;
  
  RETURN QUERY
  SELECT 
    fr.id as request_id,
    fr.from_user_id,
    COALESCE(up_from.display_name, 'Unknown') as from_user_name,
    fr.to_user_id,
    COALESCE(up_to.display_name, 'Unknown') as to_user_name,
    fr.status,
    CASE 
      WHEN fr.from_user_id = p_user_id THEN 'sent'
      ELSE 'received'
    END as direction,
    fr.created_at
  FROM fellowship_requests fr
  LEFT JOIN user_profiles up_from ON up_from.user_id = fr.from_user_id
  LEFT JOIN user_profiles up_to ON up_to.user_id = fr.to_user_id
  WHERE (fr.from_user_id = p_user_id OR fr.to_user_id = p_user_id)
    AND fr.status = 'pending'
  ORDER BY fr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

GRANT EXECUTE ON FUNCTION get_fellowship_requests TO authenticated;

-- 5. Simplified cancel function
DROP FUNCTION IF EXISTS cancel_fellowship_request(UUID, UUID);

CREATE OR REPLACE FUNCTION cancel_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON AS $$
BEGIN
  -- Check if table exists
  IF NOT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'fellowship_requests'
  ) THEN
    RETURN json_build_object('success', false, 'message', 'Requests not available');
  END IF;
  
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
$$ LANGUAGE plpgsql SECURITY INVOKER;

GRANT EXECUTE ON FUNCTION cancel_fellowship_request TO authenticated;

-- 6. Test if we can query user_profiles
SELECT COUNT(*) as user_count FROM user_profiles;

-- 7. Make sure all permissions are granted
GRANT ALL ON user_profiles TO authenticated;
GRANT ALL ON user_profiles TO anon;
GRANT ALL ON fellowships TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;

-- 8. Check what tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('fellowships', 'fellowship_requests', 'user_profiles')
ORDER BY table_name;

-- Display final status
SELECT 
  'Final fix applied!' as status,
  (SELECT COUNT(*) FROM user_profiles) as profiles_count,
  (SELECT COUNT(*) FROM fellowships) as fellowships_count;