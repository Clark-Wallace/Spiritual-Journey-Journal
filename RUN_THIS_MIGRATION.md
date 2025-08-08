# IMPORTANT: Run Fellowship Migration

The fellowship feature isn't working because the database table doesn't exist yet.

## Steps to Fix:

1. Go to your Supabase Dashboard: https://supabase.com/dashboard/project/zzociwrszcgrjenqqusp

2. Click on "SQL Editor" in the left sidebar

3. Copy and paste ALL of this SQL code:

```sql
-- Fellowship System Schema
-- Create fellowship relationships table
CREATE TABLE IF NOT EXISTS fellowships (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fellow_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Prevent duplicate relationships
  UNIQUE(user_id, fellow_id),
  -- Prevent self-fellowship
  CHECK (user_id != fellow_id)
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_fellowships_user_id ON fellowships(user_id);
CREATE INDEX IF NOT EXISTS idx_fellowships_fellow_id ON fellowships(fellow_id);

-- Enable RLS
ALTER TABLE fellowships ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can add fellowships" ON fellowships;
DROP POLICY IF EXISTS "Users can remove own fellowships" ON fellowships;

-- Create new policies
CREATE POLICY "Users can view own fellowships" ON fellowships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = fellow_id);

CREATE POLICY "Users can add fellowships" ON fellowships
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove own fellowships" ON fellowships
  FOR DELETE USING (auth.uid() = user_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE fellowships;

-- Function to get all fellowship members for a user
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
    COALESCE(u.raw_user_meta_data->>'name', u.email) as fellow_name,
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
```

4. Click "Run" button

5. You should see "Success. No rows returned" message

6. Refresh your app and try the fellowship feature again

## To Verify It Worked:

After running the SQL, you can check if the table was created:

```sql
SELECT * FROM fellowships;
```

This should return an empty table (or any fellowships you've already added).

## Troubleshooting:

If you get an error saying "table already exists", that's fine! It means the table was created but there might be an issue with the RLS policies. Run this to check:

```sql
SELECT * FROM pg_policies WHERE tablename = 'fellowships';
```

This will show you the active policies on the table.