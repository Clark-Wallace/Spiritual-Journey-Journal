-- Force add memberships for existing groups

-- 1. First, check what groups exist
SELECT 'Existing groups:' as check;
SELECT id, name, created_by FROM fellowship_groups;

-- 2. Check current memberships
SELECT 'Current memberships before fix:' as check;
SELECT * FROM fellowship_group_members;

-- 3. Temporarily disable RLS to ensure we can insert
ALTER TABLE fellowship_group_members DISABLE ROW LEVEL SECURITY;

-- 4. Force insert memberships for ALL groups based on their creators
DO $$
DECLARE
    group_record RECORD;
    insert_count INTEGER := 0;
BEGIN
    FOR group_record IN 
        SELECT id, name, created_by 
        FROM fellowship_groups 
        WHERE created_by IS NOT NULL
    LOOP
        BEGIN
            INSERT INTO fellowship_group_members (group_id, user_id, role, is_active)
            VALUES (group_record.id, group_record.created_by, 'admin', true);
            
            insert_count := insert_count + 1;
            RAISE NOTICE 'Added membership for group % (%)', group_record.name, group_record.id;
        EXCEPTION
            WHEN unique_violation THEN
                -- Update existing record
                UPDATE fellowship_group_members 
                SET role = 'admin', is_active = true
                WHERE group_id = group_record.id AND user_id = group_record.created_by;
                RAISE NOTICE 'Updated existing membership for group %', group_record.name;
            WHEN OTHERS THEN
                RAISE NOTICE 'Error adding membership for group %: %', group_record.name, SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Total memberships added: %', insert_count;
END $$;

-- 5. Re-enable RLS
ALTER TABLE fellowship_group_members ENABLE ROW LEVEL SECURITY;

-- 6. Verify memberships were created
SELECT 'Memberships after force insert:' as check;
SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fgm.user_id,
    fgm.role,
    fgm.is_active
FROM fellowship_groups fg
LEFT JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
ORDER BY fg.created_at DESC;

-- 7. Check specifically for your user
SELECT 'Your memberships after fix:' as check;
SELECT 
    fg.name as group_name,
    fgm.role,
    fgm.is_active,
    fg.created_at
FROM fellowship_group_members fgm
JOIN fellowship_groups fg ON fg.id = fgm.group_id
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'
ORDER BY fg.created_at DESC;

-- 8. Test get_my_fellowship_groups function
SELECT 'get_my_fellowship_groups after fix:' as check;
SELECT * FROM get_my_fellowship_groups();

-- 9. Also check if the function works with explicit user ID
SELECT 'Direct query for your groups:' as check;
SELECT 
    fg.id as group_id,
    fg.name as group_name,
    fg.description,
    fg.group_type,
    COUNT(DISTINCT fgm2.user_id) as member_count,
    fgm.role as my_role,
    fg.created_at
FROM fellowship_groups fg
INNER JOIN fellowship_group_members fgm ON fg.id = fgm.group_id
LEFT JOIN fellowship_group_members fgm2 ON fg.id = fgm2.group_id AND fgm2.is_active = true
WHERE fgm.user_id = 'a43ff393-dde1-4001-b667-23f518e72499'
    AND fgm.is_active = true
GROUP BY fg.id, fg.name, fg.description, fg.group_type, fgm.role, fg.created_at
ORDER BY fg.created_at DESC;