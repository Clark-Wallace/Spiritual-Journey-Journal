-- Phone Authentication Schema Updates
-- Run this in your Supabase SQL editor

-- Add phone verification columns to user_profiles
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS verification_badge BOOLEAN DEFAULT false;

-- Create index for faster phone verification lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_phone_verified 
ON user_profiles(phone_verified);

-- Update RLS policies to ensure phone-verified users only
CREATE OR REPLACE FUNCTION is_phone_verified(user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_profiles 
    WHERE id = user_id 
    AND phone_verified = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update community_posts policy to require phone verification
DROP POLICY IF EXISTS "Users can create posts" ON community_posts;
CREATE POLICY "Phone-verified users can create posts" ON community_posts
  FOR INSERT WITH CHECK (
    auth.uid() = user_id 
    AND is_phone_verified(auth.uid())
  );

-- Update chat_messages policy to require phone verification
DROP POLICY IF EXISTS "Users can send messages" ON chat_messages;
CREATE POLICY "Phone-verified users can send messages" ON chat_messages
  FOR INSERT WITH CHECK (
    auth.uid() = user_id 
    AND is_phone_verified(auth.uid())
  );

-- Update encouragements policy to require phone verification
DROP POLICY IF EXISTS "Users can create encouragements" ON encouragements;
CREATE POLICY "Phone-verified users can create encouragements" ON encouragements
  FOR INSERT WITH CHECK (
    auth.uid() = user_id 
    AND is_phone_verified(auth.uid())
  );

-- Add verified badge view for UI display
CREATE OR REPLACE VIEW verified_users AS
SELECT 
  id,
  name,
  phone_verified,
  CASE 
    WHEN phone_verified = true THEN '✓'
    ELSE ''
  END as badge
FROM user_profiles;

-- Grant access to the view
GRANT SELECT ON verified_users TO authenticated;

-- Function to check if user needs phone verification
CREATE OR REPLACE FUNCTION needs_phone_verification()
RETURNS BOOLEAN AS $$
DECLARE
  is_verified BOOLEAN;
BEGIN
  SELECT phone_verified INTO is_verified
  FROM user_profiles
  WHERE id = auth.uid();
  
  RETURN COALESCE(NOT is_verified, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add trigger to auto-create user profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO user_profiles (id, name, phone_verified)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'name', 'User'),
    COALESCE((new.phone IS NOT NULL), false)
  )
  ON CONFLICT (id) DO UPDATE
  SET phone_verified = COALESCE((new.phone IS NOT NULL), user_profiles.phone_verified);
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Add phone number to user metadata (handled by Supabase Auth automatically)
-- The phone number is stored securely in auth.users table
-- and is never exposed to other users

COMMENT ON COLUMN user_profiles.phone_verified IS 'True if user has verified their phone number';
COMMENT ON COLUMN user_profiles.verified_at IS 'Timestamp when phone was verified';
COMMENT ON COLUMN user_profiles.verification_badge IS 'Display verified badge in UI';