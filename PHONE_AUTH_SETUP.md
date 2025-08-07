# Phone Authentication Setup Guide

## Overview
Phone authentication provides a robust anti-troll system by requiring users to verify their phone number before accessing the platform. This ensures one account per phone number and significantly reduces spam/trolling.

## Step 1: Enable Phone Auth in Supabase

1. Go to your Supabase Dashboard
2. Navigate to **Authentication** → **Providers**
3. Find **Phone** in the list and enable it
4. Configure SMS provider (choose one):

### Option A: Twilio (Recommended for Production)
```
SMS Provider: Twilio
Account SID: Your Twilio Account SID
Auth Token: Your Twilio Auth Token
Message Service SID: Your Twilio Message Service SID
```

### Option B: MessageBird
```
SMS Provider: MessageBird
Access Key: Your MessageBird Access Key
Originator: Your sender name/number
```

### Option C: Supabase Test Provider (Development Only)
```
SMS Provider: Test Provider
Note: This sends codes to Supabase logs instead of real SMS
```

## Step 2: Configure SMS Templates

In Supabase Dashboard → Authentication → Templates → SMS Message:

```
Your Spiritual Journey verification code is: {{.Code}}

This code expires in 60 seconds.

God bless 🙏
```

## Step 3: Run Database Migrations

Execute the SQL in `/supabase/phone-auth-schema.sql` in your Supabase SQL Editor:

```sql
-- This adds:
-- - phone_verified column to user_profiles
-- - RLS policies requiring phone verification
-- - Helper functions for verification checks
-- - Triggers for new user creation
```

## Step 4: Environment Variables

No additional environment variables needed for phone auth - it uses your existing Supabase configuration.

## Step 5: Test the Flow

### Local Testing
1. Run `npm run dev`
2. Navigate to http://localhost:5173
3. You'll see the new phone login screen
4. Enter a phone number
5. If using test provider, check Supabase logs for the code
6. Enter verification code
7. Set your display name
8. You're in!

### Production Testing
1. Deploy to Vercel: `git push`
2. Visit your production URL
3. Complete phone verification with real SMS

## Step 6: Configure Rate Limits (Important!)

In Supabase Dashboard → Authentication → Rate Limits:

```
SMS rate limit: 5 per hour per phone number
Signup rate limit: 3 per hour per IP
```

This prevents abuse and reduces SMS costs.

## Step 7: Monitor Usage

Track your SMS usage in:
- Supabase Dashboard → Settings → Usage
- Your SMS provider dashboard (Twilio/MessageBird)

## Features Implemented

### 🛡️ Security Benefits
- **One account per phone**: Prevents multiple troll accounts
- **Ban persistence**: Can't evade bans with new emails
- **Verified users only**: All interactions require verification
- **Privacy protected**: Phone numbers never exposed to other users

### 🎨 UI Components
- **PhoneLogin.svelte**: Beautiful 3-step verification flow
- **VerifiedBadge.svelte**: Green checkmark for verified users
- **Step indicators**: Clear progress through verification
- **Country code selector**: Support for international numbers

### 📱 User Experience
- Clean, cathedral-themed login screen
- Auto-formatting for phone numbers
- 60-second resend timer
- Clear error messages
- Remember user after verification

## Supported Countries

Default country codes included:
- 🇺🇸 United States (+1)
- 🇬🇧 United Kingdom (+44)
- 🇦🇺 Australia (+61)
- 🇮🇳 India (+91)
- 🇳🇬 Nigeria (+234)
- 🇿🇦 South Africa (+27)
- 🇵🇭 Philippines (+63)

Add more in `PhoneLogin.svelte` as needed.

## Cost Considerations

### SMS Pricing (Approximate)
- **Twilio**: $0.0075 per SMS (US)
- **MessageBird**: $0.045 per SMS (US)
- **Volume discounts** available for both

### Cost Optimization
1. Set reasonable rate limits
2. Use email as backup option (future enhancement)
3. Monitor for abuse patterns
4. Consider geographic restrictions

## Troubleshooting

### "Failed to send verification code"
- Check SMS provider credentials
- Verify phone number format
- Check rate limits

### "Invalid verification code"
- Code expires after 60 seconds
- Ensure correct phone number
- Check for typos in code

### Users can't receive SMS
- Some VoIP numbers not supported
- International numbers may have delays
- Check SMS provider logs

## Future Enhancements

- [ ] WhatsApp verification option
- [ ] Email fallback for countries with SMS issues
- [ ] Trusted user program (skip verification for established members)
- [ ] Admin dashboard for managing verified users
- [ ] Block list for problematic phone numbers

## Migration from Email Auth

For existing users with email accounts:
1. They'll be prompted to verify phone on next login
2. Their data remains intact
3. Email can be kept as backup authentication

## Security Note

Phone verification significantly reduces trolling but isn't perfect:
- VoIP numbers can sometimes be used
- Determined trolls may use multiple phones
- Combine with community reporting for best results

## Support

For issues with phone authentication:
1. Check Supabase status page
2. Verify SMS provider service status
3. Review authentication logs in Supabase
4. Contact support with error details

---

*"Let your conversation be always full of grace, seasoned with salt, so that you may know how to answer everyone." - Colossians 4:6*