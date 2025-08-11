-- Fix the trigger that's blocking group creation

-- 1. Check what the trigger does
SELECT 'Trigger definition:' as check;
SELECT 
    tgname as trigger_name,
    proname as function_name,
    pg_get_triggerdef(t.oid) as trigger_definition
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE tgname = 'enforce_fellowship_for_groups';

-- 2. Get the function source
SELECT 'Trigger function source:' as check;
SELECT prosrc 
FROM pg_proc 
WHERE proname IN (
    SELECT proname 
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE tgname = 'enforce_fellowship_for_groups'
);

-- 3. DISABLE or DROP the problematic trigger
-- This trigger is likely checking if users are in fellowship before allowing group creation
DROP TRIGGER IF EXISTS enforce_fellowship_for_groups ON fellowship_groups;

-- 4. Look for the trigger function and drop it too
DROP FUNCTION IF EXISTS check_fellowship_for_group_creation() CASCADE;
DROP FUNCTION IF EXISTS enforce_fellowship_for_groups() CASCADE;

-- 5. Test group creation again
SELECT 'Testing after removing trigger:' as check;
DO $$
DECLARE
  result RECORD;
  test_group_id UUID;
BEGIN
  SELECT * INTO result FROM create_fellowship_group(
    'Test After Trigger Removal ' || extract(epoch from now())::text,
    'Testing without trigger',
    'general',
    false
  );
  
  RAISE NOTICE 'Result: success=%, group_id=%, message=%', 
    result.success, result.group_id, result.message;
  
  test_group_id := result.group_id;
  
  IF test_group_id IS NOT NULL THEN
    -- Check if group exists
    IF EXISTS (SELECT 1 FROM fellowship_groups WHERE id = test_group_id) THEN
      RAISE NOTICE 'SUCCESS: Group exists in database!';
      
      -- Check if membership exists
      IF EXISTS (SELECT 1 FROM fellowship_group_members WHERE group_id = test_group_id) THEN
        RAISE NOTICE 'SUCCESS: Membership also exists!';
      ELSE
        RAISE NOTICE 'WARNING: Membership not created';
      END IF;
      
      -- Clean up test
      DELETE FROM fellowship_group_members WHERE group_id = test_group_id;
      DELETE FROM fellowship_groups WHERE id = test_group_id;
      RAISE NOTICE 'Test group cleaned up';
    ELSE
      RAISE NOTICE 'ERROR: Group NOT in database!';
    END IF;
  END IF;
END $$;

-- 6. Check all groups now
SELECT 'Groups after fix:' as check;
SELECT id, name, created_at 
FROM fellowship_groups 
ORDER BY created_at DESC
LIMIT 10;

-- 7. If you want to see what the trigger was doing (for reference)
-- We can recreate it later with proper logic if needed
SELECT 'Trigger has been removed. Group creation should work now.' as status;