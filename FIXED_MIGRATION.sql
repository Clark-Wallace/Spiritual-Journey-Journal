-- Fixed Fellowship Migration (handles existing table)
-- Run this in Supabase SQL Editor

-- First, let's check what exists
DO $$ 
BEGIN
    -- Check if table exists, if not create it
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fellowships') THEN
        CREATE TABLE fellowships (
            id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
            user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            fellow_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE(user_id, fellow_id),
            CHECK (user_id != fellow_id)
        );
    END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_fellowships_user_id ON fellowships(user_id);
CREATE INDEX IF NOT EXISTS idx_fellowships_fellow_id ON fellowships(fellow_id);

-- Enable RLS
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure they're correct
DROP POLICY IF EXISTS "Users can view own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can add fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can remove own fellowships" ON fellowships;

-- Create policies
CREATE POLICY "Users can view own fellowships" ON fellowships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = fellow_id);

CREATE POLICY "Users can add fellowships" ON fellowships
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove own fellowships" ON fellowships
  FOR DELETE USING (auth.uid() = user_id);

-- Create or replace the function to get fellowship members
CREATE OR REPLACE FUNCTION get_fellowship_members(for_user_id UUID)
RETURNS TABLE(
  fellow_id UUID,
  fellow_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    CASE 
      WHEN f.user_id = for_user_id THEN f.fellow_id
      ELSE f.user_id
    END as fellow_id,
    COALESCE(
      u.raw_user_meta_data->>'name',
      split_part(u.email, '@', 1)
    ) as fellow_name,
    f.created_at
  FROM fellowships f
  JOIN auth.users u ON u.id = CASE 
    WHEN f.user_id = for_user_id THEN f.fellow_id
    ELSE f.user_id
  END
  WHERE f.user_id = for_user_id OR f.fellow_id = for_user_id
  ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Grant necessary permissions
GRANT ALL ON fellowships TO authenticated;
GRANT EXECUTE ON FUNCTION get_fellowship_members TO authenticated;

-- Test query to verify everything is working
SELECT 
  'Table exists' as check_item,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'fellowships') as status
UNION ALL
SELECT 
  'RLS enabled' as check_item,
  relrowsecurity as status
FROM pg_class 
WHERE relname = 'fellowships'
UNION ALL
SELECT 
  'Policies exist' as check_item,
  COUNT(*) > 0 as status
FROM pg_policies 
WHERE tablename = 'fellowships';