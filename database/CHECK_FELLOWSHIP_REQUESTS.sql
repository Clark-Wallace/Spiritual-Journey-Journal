-- Check current fellowship requests in the database
-- Run this to see all pending fellowship requests

-- View all pending requests
SELECT 
  fr.id,
  fr.from_user_id,
  from_profile.display_name as from_user_name,
  fr.to_user_id,
  to_profile.display_name as to_user_name,
  fr.status,
  fr.created_at,
  fr.responded_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE fr.status = 'pending'
ORDER BY fr.created_at DESC;

-- Count pending requests per user
SELECT 
  to_profile.display_name as user_name,
  fr.to_user_id,
  COUNT(*) as pending_requests
FROM fellowship_requests fr
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE fr.status = 'pending'
GROUP BY fr.to_user_id, to_profile.display_name;

-- Check if realtime is enabled
SELECT 
  schemaname,
  tablename 
FROM 
  pg_publication_tables 
WHERE 
  pubname = 'supabase_realtime'
  AND tablename = 'fellowship_requests';