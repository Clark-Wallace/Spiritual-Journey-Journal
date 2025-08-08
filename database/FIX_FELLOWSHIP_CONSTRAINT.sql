-- Fix the fellowship constraint that's preventing requests from being created

-- First, let's see what constraints exist on the fellowships table
SELECT 
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM 
    pg_constraint con
    INNER JOIN pg_namespace nsp ON nsp.oid = con.connamespace
    INNER JOIN pg_class cls ON cls.oid = con.conrelid
WHERE 
    cls.relname = 'fellowships'
    AND nsp.nspname = 'public';

-- The error suggests there's a check constraint preventing self-fellowships
-- Let's drop the problematic constraint
ALTER TABLE fellowships DROP CONSTRAINT IF EXISTS fellowships_check;

-- Also drop any constraint that might prevent user from being their own fellow
ALTER TABLE fellowships DROP CONSTRAINT IF EXISTS check_user_not_self;
ALTER TABLE fellowships DROP CONSTRAINT IF EXISTS fellowships_user_fellow_check;

-- Now add a proper constraint that prevents self-fellowship
-- but allows all other combinations
ALTER TABLE fellowships 
ADD CONSTRAINT fellowships_no_self_reference 
CHECK (user_id != fellow_id);

-- Also ensure the unique constraint exists
ALTER TABLE fellowships 
DROP CONSTRAINT IF EXISTS fellowships_user_fellow_unique;

ALTER TABLE fellowships 
ADD CONSTRAINT fellowships_user_fellow_unique 
UNIQUE (user_id, fellow_id);

-- Test that we can now insert fellowships (except self-references)
-- This should work:
-- INSERT INTO fellowships (user_id, fellow_id) 
-- VALUES ('user-id-1', 'user-id-2')
-- ON CONFLICT DO NOTHING;

-- Verify the final constraints
SELECT 
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM 
    pg_constraint con
    INNER JOIN pg_namespace nsp ON nsp.oid = con.connamespace
    INNER JOIN pg_class cls ON cls.oid = con.conrelid
WHERE 
    cls.relname = 'fellowships'
    AND nsp.nspname = 'public'
ORDER BY con.conname;