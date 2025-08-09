-- Resync fellowships to ensure consistency

-- 1. Show current state
SELECT 'Current fellowship requests:' as info;
SELECT 
  fr.id,
  from_profile.display_name as from_name,
  to_profile.display_name as to_name,
  fr.status,
  fr.created_at
FROM fellowship_requests fr
LEFT JOIN user_profiles from_profile ON from_profile.user_id = fr.from_user_id
LEFT JOIN user_profiles to_profile ON to_profile.user_id = fr.to_user_id
WHERE from_user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
   OR to_user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');

SELECT 'Current fellowships:' as info;
SELECT 
  user_profile.display_name as user_name,
  fellow_profile.display_name as fellow_name,
  f.created_at
FROM fellowships f
LEFT JOIN user_profiles user_profile ON user_profile.user_id = f.user_id
LEFT JOIN user_profiles fellow_profile ON fellow_profile.user_id = f.fellow_id
WHERE f.user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');

-- 2. If you want to reset and test fresh:
-- Option A: Remove the existing fellowship
/*
DELETE FROM fellowships 
WHERE (user_id = 'a43ff393-dde1-4001-b667-23f518e72499' AND fellow_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
   OR (user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c' AND fellow_id = 'a43ff393-dde1-4001-b667-23f518e72499');

-- Reset the request to pending
UPDATE fellowship_requests
SET status = 'pending', responded_at = NULL
WHERE from_user_id = 'a43ff393-dde1-4001-b667-23f518e72499' 
  AND to_user_id = 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c';
*/

-- Option B: Ensure the fellowship exists properly (if the request shows accepted)
/*
INSERT INTO fellowships (user_id, fellow_id)
VALUES 
  ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c'),
  ('ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c', 'a43ff393-dde1-4001-b667-23f518e72499')
ON CONFLICT (user_id, fellow_id) DO NOTHING;
*/