-- Simple diagnostic to check groups and memberships

-- 1. Count all groups
SELECT COUNT(*) as total_groups FROM fellowship_groups;

-- 2. Show ALL groups (no filter)
SELECT id, name, created_by, created_at 
FROM fellowship_groups 
ORDER BY created_at DESC;

-- 3. Count all memberships
SELECT COUNT(*) as total_memberships FROM fellowship_group_members;

-- 4. Show ALL memberships
SELECT 
    fgm.group_id,
    fgm.user_id,
    fgm.role,
    fgm.is_active,
    fg.name as group_name
FROM fellowship_group_members fgm
LEFT JOIN fellowship_groups fg ON fg.id = fgm.group_id
ORDER BY fgm.joined_at DESC;

-- 5. Specifically check your user's memberships
SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fgm.role,
    fgm.is_active,
    fgm.joined_at,
    fg.created_by
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;

-- 6. Check if you created any groups
SELECT 
    id,
    name,
    created_at
FROM fellowship_groups
WHERE created_by = 'a43ff393-dde1-4001-b667-23f518e72499'::UUID;

-- 7. Test the RPC function directly
SELECT * FROM get_my_fellowship_groups();