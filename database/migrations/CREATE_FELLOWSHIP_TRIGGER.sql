-- Create a trigger to automatically create mutual fellowship relationships
-- When user A adds user B to fellowship, automatically add user B -> user A

-- First, create the trigger function
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

-- Drop the trigger if it exists
DROP TRIGGER IF EXISTS create_mutual_fellowship_trigger ON fellowships;

-- Create the trigger
CREATE TRIGGER create_mutual_fellowship_trigger
AFTER INSERT ON fellowships
FOR EACH ROW
EXECUTE FUNCTION create_mutual_fellowship();

-- Also ensure we have a unique constraint to prevent duplicates
ALTER TABLE fellowships 
DROP CONSTRAINT IF EXISTS fellowships_user_fellow_unique;

ALTER TABLE fellowships 
ADD CONSTRAINT fellowships_user_fellow_unique 
UNIQUE (user_id, fellow_id);

-- Test that the trigger works
-- When this runs, it should automatically create both directions
SELECT 'Trigger created successfully. Mutual fellowships will now be created automatically.' as status;