-- Check if the fellowship relationship exists

-- 1. Check fellowships for both users
SELECT 
  f.user_id,
  user_profile.display_name as user_name,
  f.fellow_id,
  fellow_profile.display_name as fellow_name,
  f.created_at
FROM fellowships f
LEFT JOIN user_profiles user_profile ON user_profile.user_id = f.user_id
LEFT JOIN user_profiles fellow_profile ON fellow_profile.user_id = f.fellow_id
WHERE f.user_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
   OR f.fellow_id IN ('a43ff393-dde1-4001-b667-23f518e72499', 'ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c')
ORDER BY f.created_at DESC;

-- 2. Test what get_fellowship_members returns for Clark Wallace
SELECT * FROM get_fellowship_members('ba70f679-cadf-4cca-ab9b-a86b9aa8cd8c');

-- 3. Test what get_fellowship_members returns for Clark AI  
SELECT * FROM get_fellowship_members('a43ff393-dde1-4001-b667-23f518e72499');

-- 4. Count total fellowships
SELECT COUNT(*) as total_fellowships FROM fellowships;