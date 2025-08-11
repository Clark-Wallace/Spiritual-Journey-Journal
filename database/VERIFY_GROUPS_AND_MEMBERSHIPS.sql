-- Verify groups and memberships are working

-- 1. Check memberships for these groups
SELECT 'Memberships for your groups:' as check;
SELECT 
    fg.name as group_name,
    fgm.user_id,
    fgm.role,
    fgm.is_active,
    fgm.joined_at
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
WHERE fg.created_by = 'a43ff393-dde1-4001-b667-23f518e72499'
ORDER BY fg.created_at DESC;

-- 2. If no memberships, add them retroactively
INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
SELECT 
    id as group_id,
    created_by as user_id,
    'admin' as role,
    true as is_active
FROM fellowship_groups
WHERE created_by = 'a43ff393-dde1-4001-b667-23f518e72499'
ON CONFLICT (group_id, user_id) DO UPDATE
SET role = 'admin', is_active = true;

-- 3. Check memberships again after insert
SELECT 'After adding memberships:' as check;
SELECT 
    fg.name as group_name,
    fgm.role,
    fgm.is_active
FROM fellowship_groups fg
JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499';

-- 4. Test the get_my_fellowship_groups function
SELECT 'get_my_fellowship_groups result:' as check;
SELECT * FROM get_my_fellowship_groups();

-- 5. Check which groups are public
SELECT 'Public groups (for Discover tab):' as check;
SELECT 
    id,
    name,
    is_private,
    created_by
FROM fellowship_groups
WHERE is_private = false;

-- 6. Verify the SELECT policy allows viewing public groups
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a43ff393-dde1-4001-b667-23f518e72499';

SELECT 'What you can see as authenticated user:' as check;
SELECT id, name, is_private FROM fellowship_groups;

RESET ROLE;