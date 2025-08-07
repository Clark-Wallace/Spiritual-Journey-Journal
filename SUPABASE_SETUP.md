# Supabase Setup Instructions

## 1. Create a Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Sign up or log in
3. Click "New Project"
4. Fill in:
   - Project name: "WWJD Journal" (or your preferred name)
   - Database Password: (save this securely)
   - Region: Choose closest to you
5. Click "Create Project" and wait for setup (~2 minutes)

## 2. Set Up Database Schema

1. In your Supabase dashboard, go to **SQL Editor** (left sidebar)
2. Click "New Query"
3. Copy and paste the entire contents of `supabase/schema.sql`
4. Click "Run" to execute the SQL
5. You should see "Success" messages for each table created

## 3. Get Your API Keys

1. Go to **Settings** → **API** (in left sidebar)
2. Copy these values:
   - **Project URL**: `https://YOUR-PROJECT.supabase.co`
   - **anon public key**: `eyJhbGc...` (long string)

## 4. Configure Your App

1. Create a `.env` file in your svelte-app directory:
```bash
cp .env.example .env
```

2. Edit `.env` and add your values:
```env
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here
```

## 5. Enable Authentication

1. In Supabase dashboard, go to **Authentication** → **Providers**
2. Ensure **Email** is enabled (should be by default)
3. Optional: Configure email templates under **Email Templates**

## 6. Test the Setup

1. Restart your development server:
```bash
npm run dev
```

2. Try creating an account:
   - You'll receive a confirmation email
   - Click the link to verify your account
   - Sign in with your credentials

## 7. (Optional) Disable Email Confirmation for Testing

If you want to skip email confirmation during development:

1. Go to **Authentication** → **Providers** → **Email**
2. Turn OFF "Confirm email"
3. Save changes

## Security Notes

- Never commit your `.env` file to git
- The `anon` key is safe to use in frontend code (it's meant to be public)
- Row Level Security (RLS) policies protect user data
- Each user can only see/edit their own entries

## Troubleshooting

### "Invalid API key"
- Double-check your keys in `.env`
- Make sure there are no extra spaces or quotes

### "User already registered"
- Check your Supabase dashboard → Authentication → Users
- Delete test users if needed

### Can't see data after sign in
- Check browser console for errors
- Verify RLS policies are created (run schema.sql again if needed)

## Next Steps

Once setup is complete, you can:
- View your data in Supabase Table Editor
- Monitor usage in the Dashboard
- Set up additional auth providers (Google, Apple, etc.)
- Configure email templates for better branding