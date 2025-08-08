-- Complete Fellowship System Rebuild
-- Run this ENTIRE script in Supabase SQL Editor to fix everything

-- ============================================
-- STEP 1: CLEAN UP OLD FUNCTIONS
-- ============================================
DROP FUNCTION IF EXISTS get_fellowship_members CASCADE;
DROP FUNCTION IF EXISTS get_all_users_with_profiles CASCADE;
DROP FUNCTION IF EXISTS send_fellowship_request CASCADE;
DROP FUNCTION IF EXISTS accept_fellowship_request CASCADE;
DROP FUNCTION IF EXISTS decline_fellowship_request CASCADE;
DROP FUNCTION IF EXISTS cancel_fellowship_request CASCADE;
DROP FUNCTION IF EXISTS get_fellowship_requests CASCADE;
DROP FUNCTION IF EXISTS check_fellowship_status CASCADE;
DROP FUNCTION IF EXISTS get_fellowship_feed CASCADE;
DROP FUNCTION IF EXISTS upsert_user_profile CASCADE;
DROP FUNCTION IF EXISTS get_user_display_name CASCADE;
DROP FUNCTION IF EXISTS populate_all_user_profiles CASCADE;
DROP FUNCTION IF EXISTS handle_new_user CASCADE;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- ============================================
-- STEP 2: ENSURE TABLES EXIST WITH PROPER STRUCTURE
-- ============================================

-- User Profiles Table
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Fellowship Requests Table
CREATE TABLE IF NOT EXISTS fellowship_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(from_user_id, to_user_id)
);

-- Ensure fellowships table has proper structure
CREATE TABLE IF NOT EXISTS fellowships (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fellow_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, fellow_id)
);

-- ============================================
-- STEP 3: CREATE INDEXES
-- ============================================
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_from ON fellowship_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_to ON fellowship_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_fellowship_requests_status ON fellowship_requests(status);
CREATE INDEX IF NOT EXISTS idx_fellowships_user ON fellowships(user_id);
CREATE INDEX IF NOT EXISTS idx_fellowships_fellow ON fellowships(fellow_id);

-- ============================================
-- STEP 4: ENABLE RLS AND CREATE POLICIES
-- ============================================

-- User Profiles
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;

CREATE POLICY "Anyone can view profiles" ON user_profiles
  FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Fellowship Requests
ALTER TABLE fellowship_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can send requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update received requests" ON fellowship_requests;

CREATE POLICY "Users can view own requests" ON fellowship_requests
  FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);
CREATE POLICY "Users can send requests" ON fellowship_requests
  FOR INSERT WITH CHECK (auth.uid() = from_user_id);
CREATE POLICY "Users can update received requests" ON fellowship_requests
  FOR UPDATE USING (auth.uid() = to_user_id OR auth.uid() = from_user_id);

-- Fellowships
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can delete own fellowships" ON fellowships;

CREATE POLICY "Users can view own fellowships" ON fellowships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = fellow_id);
CREATE POLICY "Users can delete own fellowships" ON fellowships
  FOR DELETE USING (auth.uid() = user_id OR auth.uid() = fellow_id);

-- ============================================
-- STEP 5: CREATE SIMPLE WORKING FUNCTIONS
-- ============================================

-- 1. Simple upsert user profile
CREATE OR REPLACE FUNCTION upsert_user_profile(
  p_user_id UUID,
  p_display_name TEXT
)
RETURNS void 
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO user_profiles (user_id, display_name)
  VALUES (p_user_id, p_display_name)
  ON CONFLICT (user_id)
  DO UPDATE SET 
    display_name = EXCLUDED.display_name,
    updated_at = NOW();
END;
$$;

-- 2. Get fellowship members
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) 
LANGUAGE plpgsql
AS $$
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
$$;

-- 3. Get all users for search
CREATE OR REPLACE FUNCTION get_all_users_with_profiles()
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  email TEXT
) 
LANGUAGE sql
STABLE
AS $$
  SELECT 
    up.user_id,
    up.display_name,
    up.display_name as email
  FROM user_profiles up
  ORDER BY up.display_name;
$$;

-- 4. Send fellowship request (SIMPLIFIED)
CREATE OR REPLACE FUNCTION send_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON 
LANGUAGE plpgsql
AS $$
DECLARE
  v_existing_fellowship BOOLEAN;
  v_existing_request RECORD;
BEGIN
  -- Check if already fellows
  SELECT EXISTS(
    SELECT 1 FROM fellowships 
    WHERE user_id = p_from_user_id AND fellow_id = p_to_user_id
  ) INTO v_existing_fellowship;
  
  IF v_existing_fellowship THEN
    RETURN json_build_object('success', false, 'message', 'Already in fellowship');
  END IF;
  
  -- Check for existing pending request
  SELECT * INTO v_existing_request
  FROM fellowship_requests
  WHERE ((from_user_id = p_from_user_id AND to_user_id = p_to_user_id)
     OR (from_user_id = p_to_user_id AND to_user_id = p_from_user_id))
    AND status = 'pending'
  LIMIT 1;
  
  IF v_existing_request.id IS NOT NULL THEN
    IF v_existing_request.from_user_id = p_to_user_id THEN
      -- Mutual request - accept both
      UPDATE fellowship_requests
      SET status = 'accepted', responded_at = NOW()
      WHERE id = v_existing_request.id;
      
      INSERT INTO fellowships (user_id, fellow_id)
      VALUES 
        (p_from_user_id, p_to_user_id),
        (p_to_user_id, p_from_user_id)
      ON CONFLICT DO NOTHING;
      
      RETURN json_build_object('success', true, 'message', 'Fellowship established (mutual request)');
    ELSE
      RETURN json_build_object('success', false, 'message', 'Request already pending');
    END IF;
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
  VALUES (p_from_user_id, p_to_user_id, 'pending')
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING;
  
  RETURN json_build_object('success', true, 'message', 'Request sent');
END;
$$;

-- 5. Accept fellowship request
CREATE OR REPLACE FUNCTION accept_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSON 
LANGUAGE plpgsql
AS $$
DECLARE
  v_request RECORD;
BEGIN
  SELECT * INTO v_request
  FROM fellowship_requests
  WHERE id = p_request_id 
    AND to_user_id = p_user_id 
    AND status = 'pending';
  
  IF v_request.id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Request not found');
  END IF;
  
  UPDATE fellowship_requests
  SET status = 'accepted', responded_at = NOW()
  WHERE id = p_request_id;
  
  INSERT INTO fellowships (user_id, fellow_id)
  VALUES 
    (v_request.from_user_id, v_request.to_user_id),
    (v_request.to_user_id, v_request.from_user_id)
  ON CONFLICT DO NOTHING;
  
  RETURN json_build_object('success', true, 'message', 'Fellowship accepted');
END;
$$;

-- 6. Decline fellowship request
CREATE OR REPLACE FUNCTION decline_fellowship_request(
  p_request_id UUID,
  p_user_id UUID
)
RETURNS JSON 
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE fellowship_requests
  SET status = 'declined', responded_at = NOW()
  WHERE id = p_request_id 
    AND to_user_id = p_user_id 
    AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Request not found');
  END IF;
  
  RETURN json_build_object('success', true, 'message', 'Request declined');
END;
$$;

-- 7. Cancel fellowship request
CREATE OR REPLACE FUNCTION cancel_fellowship_request(
  p_from_user_id UUID,
  p_to_user_id UUID
)
RETURNS JSON 
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM fellowship_requests
  WHERE from_user_id = p_from_user_id 
    AND to_user_id = p_to_user_id 
    AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'No pending request found');
  END IF;
  
  RETURN json_build_object('success', true, 'message', 'Request cancelled');
END;
$$;

-- 8. Get fellowship requests
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
) 
LANGUAGE plpgsql
AS $$
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
$$;

-- ============================================
-- STEP 6: GRANT ALL PERMISSIONS
-- ============================================
GRANT ALL ON user_profiles TO authenticated, anon;
GRANT ALL ON fellowship_requests TO authenticated, anon;
GRANT ALL ON fellowships TO authenticated, anon;

GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles TO authenticated, anon;
GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated, anon;
GRANT EXECUTE ON FUNCTION accept_fellowship_request TO authenticated, anon;
GRANT EXECUTE ON FUNCTION decline_fellowship_request TO authenticated, anon;
GRANT EXECUTE ON FUNCTION cancel_fellowship_request TO authenticated, anon;
GRANT EXECUTE ON FUNCTION get_fellowship_requests TO authenticated, anon;

-- ============================================
-- STEP 7: POPULATE USER PROFILES
-- ============================================

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

-- Update from chat messages
UPDATE user_profiles up
SET display_name = cm.user_name
FROM (
  SELECT DISTINCT ON (user_id) 
    user_id, 
    user_name
  FROM chat_messages
  WHERE user_name IS NOT NULL 
    AND user_name != ''
    AND user_name != 'Unknown'
  ORDER BY user_id, created_at DESC
) cm
WHERE up.user_id = cm.user_id
  AND (up.display_name = 'Unknown' OR up.display_name LIKE '%@%');

-- ============================================
-- STEP 8: CLEAN UP BAD DATA
-- ============================================

-- Remove duplicate fellowships
DELETE FROM fellowships f1
WHERE EXISTS (
  SELECT 1 FROM fellowships f2
  WHERE f2.user_id = f1.user_id 
    AND f2.fellow_id = f1.fellow_id
    AND f2.id < f1.id
);

-- Remove orphaned requests (where users don't exist)
DELETE FROM fellowship_requests
WHERE from_user_id NOT IN (SELECT id FROM auth.users WHERE deleted_at IS NULL)
   OR to_user_id NOT IN (SELECT id FROM auth.users WHERE deleted_at IS NULL);

-- ============================================
-- STEP 9: VERIFY EVERYTHING
-- ============================================
SELECT 
  'Fellowship system rebuilt!' as status,
  (SELECT COUNT(*) FROM user_profiles) as user_profiles_count,
  (SELECT COUNT(*) FROM fellowships) as fellowships_count,
  (SELECT COUNT(*) FROM fellowship_requests WHERE status = 'pending') as pending_requests;