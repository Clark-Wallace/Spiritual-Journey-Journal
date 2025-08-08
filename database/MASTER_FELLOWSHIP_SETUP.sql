-- MASTER FELLOWSHIP SETUP
-- Run this complete script to set up the fellowship system from scratch
-- Last updated: 2025-08-08

-- ============================================
-- 1. CREATE TABLES
-- ============================================

-- User profiles table (stores display names)
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Fellowship requests table
CREATE TABLE IF NOT EXISTS fellowship_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  UNIQUE(from_user_id, to_user_id)
);

-- Fellowships table (mutual relationships)
CREATE TABLE IF NOT EXISTS fellowships (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fellow_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (user_id, fellow_id),
  CONSTRAINT fellowships_user_fellow_unique UNIQUE (user_id, fellow_id)
);

-- ============================================
-- 2. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowship_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 3. CREATE RLS POLICIES
-- ============================================

-- User Profiles Policies
DROP POLICY IF EXISTS "Users can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;

CREATE POLICY "Users can view all profiles" 
ON user_profiles FOR SELECT 
USING (true);

CREATE POLICY "Users can insert own profile" 
ON user_profiles FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own profile" 
ON user_profiles FOR UPDATE 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Fellowship Requests Policies
DROP POLICY IF EXISTS "Users can view relevant requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can create requests" ON fellowship_requests;
DROP POLICY IF EXISTS "Users can update requests sent to them" ON fellowship_requests;

CREATE POLICY "Users can view relevant requests" 
ON fellowship_requests FOR SELECT 
USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

CREATE POLICY "Users can create requests" 
ON fellowship_requests FOR INSERT 
WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "Users can update requests sent to them" 
ON fellowship_requests FOR UPDATE 
USING (auth.uid() = to_user_id)
WITH CHECK (auth.uid() = to_user_id);

-- Fellowships Policies
DROP POLICY IF EXISTS "Users can view all fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can insert own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can delete own fellowships" ON fellowships;

CREATE POLICY "Users can view all fellowships" 
ON fellowships FOR SELECT 
USING (true);

CREATE POLICY "Users can insert own fellowships" 
ON fellowships FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own fellowships" 
ON fellowships FOR DELETE 
USING (auth.uid() = user_id);

-- ============================================
-- 4. CREATE TRIGGER FOR MUTUAL FELLOWSHIPS
-- ============================================

CREATE OR REPLACE FUNCTION create_mutual_fellowship()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if the reverse fellowship already exists
  IF NOT EXISTS (
    SELECT 1 FROM fellowships 
    WHERE user_id = NEW.fellow_id 
    AND fellow_id = NEW.user_id
  ) THEN
    -- Create the reverse fellowship
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES (NEW.fellow_id, NEW.user_id)
    ON CONFLICT (user_id, fellow_id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS create_mutual_fellowship_trigger ON fellowships;

CREATE TRIGGER create_mutual_fellowship_trigger
AFTER INSERT ON fellowships
FOR EACH ROW
EXECUTE FUNCTION create_mutual_fellowship();

-- ============================================
-- 5. CREATE RPC FUNCTIONS
-- ============================================

-- Send fellowship request
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
  -- Check if already in fellowship
  SELECT * INTO v_existing_fellowship
  FROM fellowships
  WHERE user_id = p_from_user_id AND fellow_id = p_to_user_id;
  
  IF v_existing_fellowship IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'Already in fellowship');
  END IF;
  
  -- Check for existing request from us to them
  SELECT * INTO v_existing_request
  FROM fellowship_requests
  WHERE from_user_id = p_from_user_id 
    AND to_user_id = p_to_user_id
    AND status = 'pending';
  
  IF v_existing_request IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'Request already pending');
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
    INSERT INTO fellowships (user_id, fellow_id)
    VALUES 
      (p_from_user_id, p_to_user_id),
      (p_to_user_id, p_from_user_id)
    ON CONFLICT DO NOTHING;
    
    RETURN jsonb_build_object('success', true, 'message', 'Fellowship established (mutual request)');
  END IF;
  
  -- Create new request
  INSERT INTO fellowship_requests (from_user_id, to_user_id, status)
  VALUES (p_from_user_id, p_to_user_id, 'pending');
  
  RETURN jsonb_build_object('success', true, 'message', 'Fellowship request sent');
END;
$$;

-- Accept fellowship request
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
    RETURN jsonb_build_object('success', false, 'message', 'Request not found or already processed');
  END IF;
  
  -- Update the request status
  UPDATE fellowship_requests
  SET status = 'accepted', responded_at = NOW()
  WHERE id = p_request_id;
  
  -- Create both sides of the fellowship
  INSERT INTO fellowships (user_id, fellow_id)
  VALUES 
    (v_request.from_user_id, v_request.to_user_id),
    (v_request.to_user_id, v_request.from_user_id)
  ON CONFLICT (user_id, fellow_id) DO NOTHING;
  
  RETURN jsonb_build_object('success', true, 'message', 'Fellowship request accepted');
END;
$$;

-- Decline fellowship request
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
  UPDATE fellowship_requests
  SET status = 'declined', responded_at = NOW()
  WHERE id = p_request_id
    AND to_user_id = p_user_id
    AND status = 'pending';
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request not found or already processed');
  END IF;
  
  RETURN jsonb_build_object('success', true, 'message', 'Fellowship request declined');
END;
$$;

-- Get fellowship members
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Get fellowship requests
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
      WHEN fr.from_user_id = p_user_id THEN 'sent'
      ELSE 'received'
    END as direction
  FROM fellowship_requests fr
  LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
  LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
  WHERE (fr.from_user_id = p_user_id OR fr.to_user_id = p_user_id)
    AND fr.status = 'pending'
  ORDER BY fr.created_at DESC;
END;
$$;

-- Get all users with profiles
CREATE OR REPLACE FUNCTION get_all_users_with_profiles()
RETURNS TABLE(user_id UUID, display_name TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT up.user_id, up.display_name
  FROM user_profiles up
  ORDER BY up.display_name;
END;
$$;

-- ============================================
-- 6. GRANT PERMISSIONS
-- ============================================

GRANT ALL ON user_profiles TO authenticated;
GRANT SELECT ON user_profiles TO anon;
GRANT ALL ON fellowship_requests TO authenticated;
GRANT ALL ON fellowships TO authenticated;

GRANT EXECUTE ON FUNCTION send_fellowship_request(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION accept_fellowship_request(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION decline_fellowship_request(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_members(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_requests(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles() TO authenticated;

-- ============================================
-- 7. POPULATE INITIAL DATA (if needed)
-- ============================================

-- Populate user_profiles from existing data if not already present
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  COALESCE(
    MAX(user_name),
    SPLIT_PART(MAX(user_id::text), '-', 1)
  ) as display_name
FROM (
  SELECT user_id, user_name FROM community_posts WHERE user_name IS NOT NULL
  UNION
  SELECT user_id, user_name FROM chat_messages WHERE user_name IS NOT NULL
) combined_users
GROUP BY user_id
ON CONFLICT (user_id) DO NOTHING;

-- ============================================
-- Done! The fellowship system is ready to use.
-- ============================================