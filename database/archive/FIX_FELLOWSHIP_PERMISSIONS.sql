-- Fix Fellowship Permissions - Run this in Supabase SQL Editor
-- This fixes the permission denied errors for auth.users table

-- 1. Drop and recreate get_fellowship_members without auth.users reference
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

-- 2. Fix get_all_users_with_profiles to not directly access auth.users
DROP FUNCTION IF EXISTS get_all_users_with_profiles();

-- Instead, we'll create a simpler version that uses user_profiles
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
    up.display_name as email -- Use display_name instead of email for privacy
  FROM user_profiles up
  ORDER BY up.display_name;
END;
$$ LANGUAGE plpgsql;

-- 3. Fix get_fellowship_feed function
DROP FUNCTION IF EXISTS get_fellowship_feed(UUID);

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
      ELSE COALESCE(up.display_name, cp.user_name, 'Unknown')
    END as user_name,
    cp.content,
    cp.share_type,
    cp.is_anonymous,
    cp.created_at
  FROM community_posts cp
  LEFT JOIN user_profiles up ON up.user_id = cp.user_id
  WHERE cp.user_id IN (
    SELECT fellow_id FROM fellowships WHERE user_id = for_user_id
    UNION
    SELECT for_user_id -- Include own posts
  )
  ORDER BY cp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql;

-- 4. Fix get_user_display_name function
DROP FUNCTION IF EXISTS get_user_display_name(UUID);

CREATE OR REPLACE FUNCTION get_user_display_name(p_user_id UUID)
RETURNS TEXT AS $$
BEGIN
  RETURN (
    SELECT COALESCE(display_name, 'Unknown')
    FROM user_profiles
    WHERE user_id = p_user_id
    LIMIT 1
  );
END;
$$ LANGUAGE plpgsql;

-- 5. Create a function to populate user_profiles for all existing users
CREATE OR REPLACE FUNCTION populate_all_user_profiles()
RETURNS void AS $$
DECLARE
  user_record RECORD;
BEGIN
  -- Loop through all auth users and create profiles if missing
  FOR user_record IN 
    SELECT id, email, raw_user_meta_data->>'name' as name
    FROM auth.users
    WHERE deleted_at IS NULL
  LOOP
    INSERT INTO user_profiles (user_id, display_name)
    VALUES (
      user_record.id,
      COALESCE(
        user_record.name,
        SPLIT_PART(user_record.email::TEXT, '@', 1)
      )
    )
    ON CONFLICT (user_id) DO NOTHING;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run the population function once
SELECT populate_all_user_profiles();

-- 6. Grant all necessary permissions
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_feed TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_display_name TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION send_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION accept_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION decline_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_fellowship_request TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_requests TO authenticated;
GRANT EXECUTE ON FUNCTION check_fellowship_status TO authenticated;

-- 7. Ensure user_profiles table has proper permissions
GRANT ALL ON user_profiles TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;

-- 8. Create a trigger to automatically create user_profiles on signup
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
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create trigger for new users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Display completion status
SELECT 
  'Permissions fixed!' as status,
  COUNT(*) as total_profiles
FROM user_profiles;