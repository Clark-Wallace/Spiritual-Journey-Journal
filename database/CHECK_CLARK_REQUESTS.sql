-- Check what requests exist for Clark AI and Clark Wallace

-- 1. Show ALL 6 requests with details
SELECT 
  fr.id,
  fr.from_user_id,
  from_profile.display_name as from_name,
  fr.to_user_id,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
ORDER BY fr.created_at DESC;

-- 2. Check specifically for requests TO Clark Wallace that are pending
SELECT 
  fr.id,
  fr.from_user_id,
  from_profile.display_name as from_name,
  fr.to_user_id,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE fr.to_user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c'  -- Clark Wallace
  AND fr.status = 'pending';

-- 3. Test what the RPC function returns for Clark Wallace
SELECT * FROM get_fellowship_requests('ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');

-- 4. Check if there's a pending request from Clark AI to Clark Wallace
SELECT 
  id,
  from_user_id,
  to_user_id,
  status,
  created_at
FROM fellowship_requests
WHERE from_user_id = 'a43ff393-dde1-4001-b667-23f518e72499'  -- Clark AI
  AND to_user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c'   -- Clark Wallace
ORDER BY created_at DESC;