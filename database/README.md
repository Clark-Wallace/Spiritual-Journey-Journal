# Database Migrations and Scripts

## Quick Start

To set up the fellowship system from scratch, run:
```sql
database/MASTER_FELLOWSHIP_SETUP.sql
```

This master script includes everything needed for the fellowship system:
- Tables creation
- RLS policies
- Triggers for mutual fellowships
- RPC functions
- Proper permissions

## Folder Structure

### `/database`
- `MASTER_FELLOWSHIP_SETUP.sql` - Complete fellowship system setup (run this first!)

### `/database/migrations`
Individual migration files if you need to run them separately:
- `CREATE_FELLOWSHIP_REQUESTS.sql` - Initial fellowship requests table
- `CREATE_FELLOWSHIP_TRIGGER.sql` - Trigger for mutual fellowship creation
- `FIX_USER_PROFILES_RLS.sql` - RLS policies for user_profiles
- `FIX_FELLOWSHIPS_RLS.sql` - RLS policies for fellowships table
- `CLEANUP_FELLOWSHIP_POLICIES.sql` - Remove duplicate policies
- `FIX_ACCEPT_FELLOWSHIP_RPC.sql` - Fix RPC functions with SECURITY DEFINER

### `/database/archive`
Older SQL files from development iterations (kept for reference)

## Fellowship System Overview

The fellowship system uses:
1. **user_profiles** - Stores display names for users
2. **fellowship_requests** - Tracks pending/accepted/declined requests
3. **fellowships** - Stores mutual fellowship relationships
4. **RPC functions** - Handle request sending, accepting, declining
5. **Triggers** - Automatically create mutual fellowships

## Common Issues & Solutions

### 403 Forbidden Errors
- Run `MASTER_FELLOWSHIP_SETUP.sql` to ensure all RLS policies are correct
- RPC functions use SECURITY DEFINER to bypass RLS when needed

### Users Showing as "Unknown"
- Ensure user_profiles table is populated
- New users should have profiles created on signup (handled in app code)

### Fellowship Not Mutual
- The trigger should handle this automatically
- If not working, check that the trigger exists and uses SECURITY DEFINER

## Running Migrations

1. Go to your Supabase project dashboard
2. Navigate to SQL Editor
3. Copy and paste the contents of the SQL file
4. Click "Run" to execute

Always run `MASTER_FELLOWSHIP_SETUP.sql` for a complete setup!