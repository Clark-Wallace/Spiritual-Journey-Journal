-- Update Fellowship Search to Find All Users
-- Run this in Supabase SQL Editor

-- Create a function to get all auth users with their profiles
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
    COALESCE(up.display_name, au.email::TEXT) as display_name,
    au.email::TEXT as email
  FROM auth.users au
  LEFT JOIN user_profiles up ON up.user_id = au.id
  WHERE au.deleted_at IS NULL
  ORDER BY COALESCE(up.display_name, au.email::TEXT);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_all_users_with_profiles TO authenticated;

-- Update the fellowship feed query function
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
    COALESCE(up.display_name, cp.user_name, 'Unknown') as user_name,
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

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_fellowship_feed TO authenticated;

SELECT 'Fellowship search and feed functions updated!' as status;