-- Create Missing Tables and Fix Fellowship System
-- Run this entire script in Supabase SQL Editor

-- 1. Create user_profiles table (MISSING!)
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);

-- Enable RLS
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;

-- Create policies for user_profiles
CREATE POLICY "Users can view all profiles" ON user_profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON user_profiles TO authenticated;
GRANT ALL ON user_profiles TO anon;

-- 2. Populate user_profiles from existing data
-- From chat_messages
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  user_name
FROM chat_messages 
WHERE user_id IS NOT NULL 
  AND user_name IS NOT NULL
  AND user_name != ''
ON CONFLICT (user_id) DO NOTHING;

-- From community_posts
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  user_name
FROM community_posts 
WHERE user_id IS NOT NULL 
  AND user_name IS NOT NULL
  AND user_name != ''
ON CONFLICT (user_id) DO UPDATE 
SET display_name = EXCLUDED.display_name
WHERE user_profiles.display_name = 'Unknown' OR user_profiles.display_name IS NULL;

-- From auth.users
INSERT INTO user_profiles (user_id, display_name)
SELECT 
  id,
  COALESCE(
    raw_user_meta_data->>'name',
    SPLIT_PART(email::TEXT, '@', 1)
  )
FROM auth.users
WHERE deleted_at IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- 3. Create/Fix the upsert function
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

-- 4. Fix fellowship_requests table structure (if needed)
ALTER TABLE fellowship_requests 
  ALTER COLUMN status SET DEFAULT 'pending';

-- 5. Create all the RPC functions
-- Get fellowship members
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    f.fellow_id,
    COALESCE(up.display_name, 'Unknown') as fellow_name,
    f.created_at
  FROM fellowships f
  LEFT JOIN user_profiles up ON up.user_id = f.fellow_id
  WHERE f.user_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Get all users for search
CREATE OR REPLACE FUNCTION get_all_users_with_profiles()
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  email TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    up.user_id,
    up.display_name,
    up.display_name as email
  FROM user_profiles up
  ORDER BY up.display_name;
END;
$$ LANGUAGE plpgsql;

-- Send fellowship request
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
    END IF;
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
  VALUES (p_from_user_id, p_to_user_id, 'pending');
  
  RETURN json_build_object('success', true, 'message', 'Request sent');
END;
$$ LANGUAGE plpgsql;

-- Accept fellowship request
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
$$ LANGUAGE plpgsql;

-- Decline fellowship request
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
$$ LANGUAGE plpgsql;

-- Cancel fellowship request
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
$$ LANGUAGE plpgsql;

-- Get fellowship requests
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
$$ LANGUAGE plpgsql;

-- 6. Grant all permissions
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles TO authenticated;
GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION accept_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION decline_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_requests TO authenticated;

-- 7. Create trigger for new users
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.user_profiles (user_id, display_name)
  VALUES (
    new.id,
    COALESCE(
      new.raw_user_meta_data->>'name',
      SPLIT_PART(new.email::TEXT, '@', 1)
    )
  )
  ON CONFLICT DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create trigger for new users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 8. Verify everything
SELECT 
  'Tables created successfully!' as status,
  (SELECT COUNT(*) FROM user_profiles) as user_profiles_count,
  (SELECT COUNT(*) FROM fellowships) as fellowships_count,
  (SELECT COUNT(*) FROM fellowship_requests) as requests_count;