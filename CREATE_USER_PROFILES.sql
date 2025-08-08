-- Create User Profiles Table to Store User Names
-- Run this in Supabase SQL Editor

-- Create a simple user_profiles table to store names
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

-- Policies
CREATE POLICY "Users can view all profiles" ON user_profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON user_profiles TO authenticated;

-- Function to upsert user profile (create or update)
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

-- Update the get_fellowship_members function to use user_profiles
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
    COALESCE(up.display_name, 'Unknown') as fellow_name,
    f.created_at
  FROM fellowships f
  LEFT JOIN user_profiles up ON up.user_id = f.fellow_id
  WHERE f.user_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;

-- Migrate existing names from chat_messages to user_profiles
INSERT INTO user_profiles (user_id, display_name)
SELECT DISTINCT 
  user_id,
  user_name
FROM chat_messages 
WHERE user_id IS NOT NULL 
  AND user_name IS NOT NULL
  AND user_name != ''
ON CONFLICT (user_id) DO NOTHING;

-- Migrate names from community_posts as well
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
WHERE user_profiles.display_name = 'Unknown';

SELECT 'User profiles table created and populated!' as status;