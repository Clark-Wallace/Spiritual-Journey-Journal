-- Debug fellowship requests to see what's in the database

-- 1. Show ALL fellowship requests with user names
SELECT 
  fr.id,
  fr.from_user_id,
  from_profile.display_name as from_name,
  fr.to_user_id,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at,
  fr.responded_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
ORDER BY fr.created_at DESC;

-- 2. Show only PENDING requests
SELECT 
  fr.id,
  from_profile.display_name as from_name,
  '→' as arrow,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE fr.status = 'pending'
ORDER BY fr.created_at DESC;

-- 3. Get Clark Wallace's user ID (you can identify which one from display_name)
SELECT user_id, display_name 
FROM user_profiles 
WHERE display_name LIKE '%Clark%';

-- 4. Once you have Clark Wallace's ID, run this to see what the RPC function returns for them
-- Replace 'CLARK_WALLACE_USER_ID' with the actual ID from step 3
-- SELECT * FROM get_fellowship_requests('CLARK_WALLACE_USER_ID');

-- 5. Check if there are any constraints or issues
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'fellowship_requests'::regclass;