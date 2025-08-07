# Deployment Guide for Spiritual Journey

## Prerequisites

Before deploying, ensure you have:
- [ ] GitHub account
- [ ] Vercel account (free tier works)
- [ ] Supabase project set up with all tables
- [ ] Domain name (optional, for custom domain)

## Step 1: Prepare Your Repository

1. **Initialize Git** (if not already done)
```bash
cd /Users/clarkwallace/Desktop/WWJD/svelte-app
git init
```

2. **Add all files**
```bash
git add .
```

3. **Create initial commit**
```bash
git commit -m "Initial commit: Spiritual Journey Christian social network"
```

4. **Create GitHub repository**
- Go to https://github.com/new
- Name: `spiritual-journey` or `spiritualjourney-app`
- Description: Use the one provided earlier
- Keep it public or private as preferred

5. **Push to GitHub**
```bash
git remote add origin https://github.com/YOUR-USERNAME/spiritual-journey.git
git branch -M main
git push -u origin main
```

## Step 2: Deploy to Vercel

### Option A: Deploy via Vercel Dashboard

1. Go to https://vercel.com
2. Click "Add New Project"
3. Import your GitHub repository
4. Configure build settings:
   - Framework Preset: `Vite`
   - Root Directory: `svelte-app` (if needed)
   - Build Command: `npm run build`
   - Output Directory: `dist`

5. Add Environment Variables:
   - `VITE_SUPABASE_URL` = Your Supabase URL
   - `VITE_SUPABASE_ANON_KEY` = Your Supabase anon key

6. Click "Deploy"

### Option B: Deploy via CLI

1. Install Vercel CLI
```bash
npm i -g vercel
```

2. Run deployment
```bash
vercel
```

3. Follow prompts:
   - Link to existing project? No
   - What's your project name? spiritual-journey
   - In which directory? ./
   - Override settings? No

4. Add environment variables
```bash
vercel env add VITE_SUPABASE_URL
vercel env add VITE_SUPABASE_ANON_KEY
```

## Step 3: Configure Custom Domain

1. In Vercel dashboard, go to your project
2. Go to Settings → Domains
3. Add `spiritualjourney.app`
4. Follow DNS configuration instructions:
   - Add A record pointing to Vercel's IP
   - Or add CNAME record to `cname.vercel-dns.com`

### DNS Settings Example

For your domain provider, add:

**Option 1: Root domain (spiritualjourney.app)**
```
Type: A
Name: @
Value: 76.76.21.21
```

**Option 2: With www**
```
Type: CNAME
Name: www
Value: cname.vercel-dns.com
```

## Step 4: Post-Deployment Checklist

- [ ] Test user registration and login
- [ ] Create a test journal entry
- [ ] Test sharing to community feed
- [ ] Send a message in "The Way" chat
- [ ] Verify real-time updates work
- [ ] Test on mobile devices
- [ ] Check all navigation tabs work

## Environment Variables Reference

| Variable | Description | Where to Find |
|----------|-------------|---------------|
| `VITE_SUPABASE_URL` | Your Supabase project URL | Supabase Dashboard → Settings → API |
| `VITE_SUPABASE_ANON_KEY` | Public anonymous key | Supabase Dashboard → Settings → API → anon public |

## Troubleshooting

### Build Fails
- Check Node version (should be 18+)
- Verify all dependencies installed
- Check for TypeScript errors: `npm run type-check`

### Database Connection Issues
- Verify Supabase environment variables
- Check RLS policies are enabled
- Ensure all SQL schemas have been run

### Real-time Not Working
- Run the `enable-realtime.sql` script
- Check Supabase Dashboard → Database → Replication
- Ensure tables have replication enabled

### Custom Domain Not Working
- Wait 24-48 hours for DNS propagation
- Verify DNS records with: `dig spiritualjourney.app`
- Check SSL certificate status in Vercel

## Continuous Deployment

After initial setup, every push to `main` branch will trigger automatic deployment:

```bash
git add .
git commit -m "Your update message"
git push origin main
```

Vercel will automatically build and deploy within 1-2 minutes.

## Monitoring

- **Vercel Dashboard**: View deployments, errors, and analytics
- **Supabase Dashboard**: Monitor database usage and connections
- **Browser Console**: Check for client-side errors

## Backup Strategy

1. **Database Backups**: Supabase provides automatic daily backups
2. **Code Backups**: GitHub serves as code backup
3. **Manual Backups**: 
```bash
# Export Supabase data
npx supabase db dump > backup.sql
```

## Security Checklist

- [x] Environment variables not in code
- [x] RLS policies enabled on all tables
- [x] Anonymous authentication for public content
- [x] HTTPS enforced (automatic with Vercel)
- [x] Sensitive operations require authentication

---

Need help? Open an issue on GitHub or check the README for support options.