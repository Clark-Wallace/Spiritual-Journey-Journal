-- Complete Fellowship Fix - Run this entire script in Supabase SQL Editor
-- This script combines all fellowship-related fixes

-- 1. Create User Profiles Table
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

-- Policies for user_profiles
CREATE POLICY "Users can view all profiles" ON user_profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON user_profiles TO authenticated;

-- 2. Create/Update upsert function
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

-- 3. Update get_fellowship_members function
DROP FUNCTION IF EXISTS get_fellowship_members(UUID);

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
    COALESCE(up.display_name, au.email::TEXT, 'Unknown') as fellow_name,
    f.created_at
  FROM fellowships f
  LEFT JOIN user_profiles up ON up.user_id = f.fellow_id
  LEFT JOIN auth.users au ON au.id = f.fellow_id
  WHERE f.user_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- 4. Create function to get all users (for search)
CREATE OR REPLACE FUNCTION get_all_users_with_profiles()
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  email TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    au.id as user_id,
    COALESCE(
      up.display_name, 
      au.raw_user_meta_data->>'name',
      SPLIT_PART(au.email::TEXT, '@', 1)
    ) as display_name,
    au.email::TEXT as email
  FROM auth.users au
  LEFT JOIN user_profiles up ON up.user_id = au.id
  WHERE au.deleted_at IS NULL
  ORDER BY COALESCE(up.display_name, au.email::TEXT);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Create fellowship feed function
CREATE OR REPLACE FUNCTION get_fellowship_feed(for_user_id UUID)
RETURNS TABLE(
  post_id UUID,
  user_id UUID,
  user_name TEXT,
  content TEXT,
  share_type TEXT,
  is_anonymous BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cp.id as post_id,
    cp.user_id,
    CASE 
      WHEN cp.is_anonymous THEN 'Anonymous'
      ELSE COALESCE(up.display_name, cp.user_name, au.email::TEXT, 'Unknown')
    END as user_name,
    cp.content,
    cp.share_type,
    cp.is_anonymous,
    cp.created_at
  FROM community_posts cp
  LEFT JOIN user_profiles up ON up.user_id = cp.user_id
  LEFT JOIN auth.users au ON au.id = cp.user_id
  WHERE cp.user_id IN (
    SELECT fellow_id FROM fellowships WHERE user_id = for_user_id
    UNION
    SELECT for_user_id -- Include own posts
  )
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_feed TO authenticated;

-- 6. Populate user_profiles from existing data

-- First, populate from auth.users metadata
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

-- Then update with names from chat_messages (more recent)
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  user_name
FROM chat_messages 
WHERE user_id IS NOT NULL 
  AND user_name IS NOT NULL
  AND user_name != ''
  AND user_name != 'Unknown'
ON CONFLICT (user_id) 
DO UPDATE SET 
  display_name = EXCLUDED.display_name,
  updated_at = NOW()
WHERE user_profiles.display_name IN ('Unknown', '') 
  OR user_profiles.display_name IS NULL
  OR user_profiles.display_name LIKE '%@%'; -- Update if it's still an email

-- Finally update with names from community_posts (if better)
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  user_name
FROM community_posts 
WHERE user_id IS NOT NULL 
  AND user_name IS NOT NULL
  AND user_name != ''
  AND user_name != 'Unknown'
ON CONFLICT (user_id) 
DO UPDATE SET 
  display_name = EXCLUDED.display_name,
  updated_at = NOW()
WHERE user_profiles.display_name IN ('Unknown', '') 
  OR user_profiles.display_name IS NULL
  OR user_profiles.display_name LIKE '%@%'; -- Update if it's still an email

-- 7. Create a view for easy user lookup (optional but helpful)
CREATE OR REPLACE VIEW user_directory AS
SELECT 
  au.id as user_id,
  COALESCE(
    up.display_name,
    au.raw_user_meta_data->>'name',
    SPLIT_PART(au.email::TEXT, '@', 1)
  ) as display_name,
  au.email,
  au.created_at as member_since,
  up.updated_at as last_profile_update
FROM auth.users au
LEFT JOIN user_profiles up ON up.user_id = au.id
WHERE au.deleted_at IS NULL;

-- Grant access to the view
GRANT SELECT ON user_directory TO authenticated;

-- 8. Function to get user display name
CREATE OR REPLACE FUNCTION get_user_display_name(p_user_id UUID)
RETURNS TEXT AS $$
BEGIN
  RETURN (
    SELECT COALESCE(
      up.display_name,
      au.raw_user_meta_data->>'name',
      SPLIT_PART(au.email::TEXT, '@', 1),
      'Unknown'
    )
    FROM auth.users au
    LEFT JOIN user_profiles up ON up.user_id = au.id
    WHERE au.id = p_user_id
    LIMIT 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_display_name TO authenticated;

-- Display completion message
SELECT 
  'Fellowship system fully updated!' as status,
  COUNT(*) as total_users,
  COUNT(up.user_id) as users_with_profiles
FROM auth.users au
LEFT JOIN user_profiles up ON up.user_id = au.id
WHERE au.deleted_at IS NULL;