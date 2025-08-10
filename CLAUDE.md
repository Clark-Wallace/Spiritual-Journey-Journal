# CLAUDE.md - AI Assistant Context for Spiritual Journey

## Project Overview
Spiritual Journey is a comprehensive faith-based platform built with Svelte, TypeScript, and Supabase. It combines personal spiritual journaling, community fellowship, multi-room real-time chat, and AI-powered biblical guidance into a unified spiritual growth ecosystem.

**Live URL**: https://www.spiritualjourney.app  
**GitHub**: https://github.com/Clark-Wallace/Spiritual-Journey-Journal  
**Status**: Production (Stable - Last updated: January 2025)

## Current Tech Stack
- **Frontend**: Svelte 5.35.5, TypeScript 5.8.3, Vite 7.0.4
- **Backend**: Supabase (PostgreSQL, Auth, Realtime subscriptions)
- **AI Services**: 
  - OpenAI Whisper API (voice-to-text transcription)
  - Anthropic Claude 3.5 Haiku (contextual scripture guidance)
- **Deployment**: Vercel (automatic deployments from main branch)
- **Authentication**: Supabase Auth (email/password)
- **Theme**: Custom "Illuminated Sanctuary" design system

## Core Features (All Implemented & Working)

### 1. Personal Journaling System
- **Mood Tracking**: 8 spiritual states (grateful, peaceful, joyful, hopeful, reflective, troubled, anxious, seeking)
- **Daily Gratitude**: 3-item gratitude list functionality
- **Prayer Journal**: Private prayer section with optional saving
- **Voice Input**: Desktop voice-to-text via Whisper API (60-second max)
- **Timeline View**: Collapsible journal entries organized by date
- **Fellowship Sharing**: Journal entries now share exclusively to Fellowship (not Community)
- **Streak Tracking**: Grace-based consistency system (3 entries/week maintains)

### 2. Community Wall (Public)
- **Direct Posting**: "Pin a Note" button for creating posts directly on the wall
- **Post Types**: General, Prayer Request, Testimony, Praise Report
- **Anonymous Mode**: Share vulnerable content anonymously
- **Visual Design**: Prayer wall with sticky notes aesthetic
- **Random Positioning**: Notes appear with varied colors and angles
- **Real-time Updates**: Live post additions via subscriptions
- **Prayer Counter**: Shows number of people praying
- **Public Only**: Shows only community posts (is_fellowship_only = false)

### 3. The Way - Multi-Room Chat
- **5 Themed Rooms**:
  - Fellowship Hall: General spiritual discussion
  - Prayer Chamber: Prayer requests and support
  - Scripture Study: Bible study discussions
  - Testimony: Sharing faith experiences
  - Debate Room: Theological discussions
- **Real-time Messaging**: Newest messages appear first
- **Room Presence**: See who's in each room with online count
- **User Status**: Walking in faith, In prayer, Reading Word, Away
- **Message Reactions**: Toggle reactions on messages
- **Message Flags**: "Debate Room" suggestion, "Not The Way" inappropriate flag
- **Voice Input**: Desktop-only voice messages
- **Mobile Optimized**: Full-screen responsive experience
- **Mobile Sidebar**: Slide-in user list with fellowship/chat actions
- **Private Messaging** (FULLY IMPLEMENTED):
  - Pop-out chat windows with drag and resize functionality
  - Mobile-optimized chat interface with touch support
  - Chat request system with 5-minute expiry
  - Real-time message delivery and read receipts
  - Online presence indicators using user_presence table
  - Message history with proper chronological ordering
  - Automatic scrolling to newest messages
  - Fellowship-only chat access restriction
  - Global chat management across entire app

### 4. Fellowship System (Private Circle)
- **Fellowship Connections**: Friend system for spiritual accountability
- **Request Management**: Send, accept, decline fellowship requests
- **Real-time Notifications**: Badge shows pending requests
- **Online Status**: Live presence indicators for fellowship members
- **Chat Integration**: Direct chat buttons in Fellowship Manager
- **Fellowship Feed**: Private posts visible only to fellowship members
- **Direct Posting**: Enhanced post creator with character counter (1000 max)
- **Journal Sharing**: Simplified format - shows mood emoji as "feeling 😊"
- **Post Types**: General Update, Prayer Request, Testimony, Praise Report
- **Reactions**: Pray, Love, Amen with toggle functionality (active states)
- **Encouragements**: Inline comment system with real-time updates
- **Member Management**: View profiles, remove from fellowship
- **Privacy**: All fellowship posts marked with is_fellowship_only = true

### 5. AI Scripture Guidance
- **Dual Mode**: AI-powered (Claude) with keyword fallback
- **Context-Aware**: Uses journal entries and mood for personalization
- **Scripture Display**: Beautiful modal with 2-3 relevant verses
- **Personal Application**: AI explains how verses apply to situation
- **Voice Input**: Describe situations via voice (desktop)
- **Living Scrolls**: 43 curated scripture compilations

## Database Schema

### Primary Tables
```sql
-- Core content tables
journal_entries        -- Personal journal with mood, gratitude, content, prayer
community_posts        -- Posts with is_fellowship_only flag for privacy control
chat_messages          -- Room-based messages with reactions (includes room column)
user_presence          -- Per-room online status tracking (includes room column)
fellowships            -- User-to-user connections
fellowship_requests    -- Pending fellowship invitations
user_profiles          -- User display names and metadata
private_messages       -- Direct messages between fellowship members
chat_requests          -- Chat request system with expiration

-- Interaction tables  
reactions              -- Community post reactions
encouragements         -- Comments on community posts
chat_reactions         -- Chat message reactions
message_flags          -- Inappropriate content flags
prayer_wall            -- Prayer request tracking
prayer_warriors        -- Prayer commitment tracking

-- Future features
prayers                -- Personal prayer tracking
bible_verses           -- Scripture storage with embeddings
```

### Critical Columns (Often Missing)
```sql
-- These columns must exist for app to function
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS room VARCHAR(50) DEFAULT 'fellowship';
ALTER TABLE user_presence ADD COLUMN IF NOT EXISTS current_room VARCHAR(50) DEFAULT 'fellowship';
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS prayer TEXT;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS is_fellowship_only BOOLEAN DEFAULT false;
```

### Required RPC Functions
```sql
-- Fellowship system functions (must be created)
get_fellowship_members(for_user_id UUID)
get_fellowship_requests(p_user_id UUID)  
send_fellowship_request(p_from_user_id UUID, p_to_user_id UUID)
accept_fellowship_request(p_request_id UUID, p_user_id UUID)
decline_fellowship_request(p_request_id UUID, p_user_id UUID)
cancel_fellowship_request(p_from_user_id UUID, p_to_user_id UUID)
upsert_user_profile(p_user_id UUID, p_display_name TEXT)
remove_fellowship(p_user_id UUID, p_fellow_id UUID)

-- Chat system functions
get_conversation_messages(p_user_id UUID, p_other_user_id UUID, p_limit INT, p_offset INT)
send_chat_request(p_from_user_id UUID, p_to_user_id UUID, p_from_user_name TEXT)
respond_to_chat_request(p_request_id UUID, p_user_id UUID, p_response TEXT)
get_pending_chat_requests(p_user_id UUID)

-- Fellowship feed function (often missing - causes 404/400 errors)
get_fellowship_feed(for_user_id UUID) -- See database/ADD_FELLOWSHIP_ONLY_TO_POSTS.sql
-- Note: Must DROP FUNCTION first if changing return type
```

## Environment Configuration

### Development (.env)
```bash
VITE_SUPABASE_URL=https://zzociwrszcgrjenqqusp.supabase.co
VITE_SUPABASE_ANON_KEY=[your-anon-key]
OPENAI_API_KEY=[your-openai-key]      # Required for voice
ANTHROPIC_API_KEY=[your-claude-key]   # Required for AI guidance
```

### Production (Vercel Environment Variables)
- `OPENAI_API_KEY`: Whisper API for voice transcription
- `ANTHROPIC_API_KEY`: Claude API for scripture guidance
- Both must be set in Vercel dashboard for features to work

## Common Issues & Solutions

### Fellowship Section 404/400 Error
```sql
-- Run database/COMPLETE_FELLOWSHIP_SETUP.sql in Supabase SQL editor
-- This comprehensive migration:
-- 1. Adds is_fellowship_only column
-- 2. Creates/updates get_fellowship_feed function
-- 3. Sets up reactions and encouragements tables
-- 4. Configures RLS policies
-- 5. Enables realtime subscriptions
```

### Reactions/Encouragements Not Working
```sql
-- Run database/FIX_REACTIONS_RLS.sql in Supabase SQL editor
-- This fixes Row Level Security policies for:
-- 1. Reactions table (view all, create own, delete own)
-- 2. Encouragements table (view all, create, delete own)
-- 3. Foreign key constraints
-- 4. Proper permissions
```

### Journal Sharing Not Working
- Ensure is_fellowship_only column exists in community_posts
- Check that shareToFellowship function is imported (not shareToCommunity)
- Verify fellowship connections exist for the user

### Voice Not Working
- Verify OPENAI_API_KEY is set in Vercel environment
- Must use desktop browser (mobile intentionally disabled)
- Check browser microphone permissions

### Chat Messages Not Appearing
- Ensure `room` column exists in chat_messages table
- Check `current_room` column in user_presence table
- Verify user is authenticated

### Reactions Not Toggling
```sql
-- Enable realtime for reactions
ALTER PUBLICATION supabase_realtime ADD TABLE chat_reactions;
```

### User Presence Not Showing
- Check `current_room` column exists in user_presence
- Verify cleanup of stale presence records (>5 minutes old)
- Ensure realtime subscriptions are active

## Project Structure
```
svelte-app/
├── src/
│   ├── App.svelte                    # Main app with navigation
│   ├── lib/
│   │   ├── components/
│   │   │   ├── *Illuminated.svelte   # Themed components
│   │   │   ├── TheWayIlluminated.svelte # Chat system
│   │   │   ├── TheFellowship.svelte  # Fellowship feed
│   │   │   ├── FellowshipManager.svelte # Request management
│   │   │   └── VoiceRecorder.svelte  # Voice input
│   │   ├── stores/                   # Svelte stores
│   │   ├── supabase.ts               # Supabase client
│   │   └── types.ts                  # TypeScript types
│   └── styles/
│       └── illuminated.css           # Theme styles
├── api/                               # Vercel serverless functions
│   ├── transcribe.js                 # Whisper API endpoint
│   └── guidance.js                   # Claude API endpoint
├── database/                          # SQL migrations
└── supabase/                         # Additional SQL scripts
```

## Deployment & Development

### Local Development
```bash
npm install          # Install dependencies
npm run dev          # Start dev server (port 5173)
```

### Production Deployment
```bash
git push origin main # Automatically deploys to Vercel
```

### Force Vercel Redeploy
```bash
# Create dummy commit to trigger rebuild
echo "Force deploy $(date)" > FORCE_DEPLOY.txt
git add . && git commit -m "Force Vercel redeploy" && git push
```

### Database Migrations
1. Navigate to Supabase SQL editor
2. Run scripts from `database/` folder in order

#### Private Messaging & Chat Requests
```sql
-- For private messaging functionality
database/SIMPLE_PRIVATE_MESSAGES.sql     -- Basic private messages table
database/CREATE_CHAT_REQUESTS_SAFE.sql   -- Chat request system with timeout
database/FIX_RPC_FUNCTIONS.sql          -- Fix column ambiguity in RPC functions

-- Important: App works with fallback logic even if migrations aren't run
```
3. Verify RPC functions exist (common cause of errors)

## UI/UX Design System

### Illuminated Sanctuary Theme
- **Background**: Dark (#0a0a0f) with gradient overlays
- **Primary Gold**: #ffd700 (divine accents)
- **Purple Accent**: #8a2be2 (spiritual highlights)
- **Text Hierarchy**: Divine > Holy > Light > Scripture
- **Animations**: Glow effects, floating elements, divine rays
- **Borders**: Cathedral-inspired with gradient gold

### Component Patterns
- `*Illuminated`: Full theme treatment
- `*Compact`: Space-efficient variants
- `*Collapsible`: Expandable/collapsible content
- Mobile-first responsive design
- Real-time update indicators

### Mobile Experience
- **The Way Chat**: Side-by-side Users/Exit buttons in header
- **Mobile Sidebar**: Slide-in from right with user list
- **Touch Optimized**: Proper spacing for touch targets
- **Fellowship Icons**: 
  - ✓ = In fellowship (green background)
  - ⏳ = Request pending
  - 👋 = Incoming request
  - 🤝 = Send new request
  - 💬 = Private message (fellowship only)

## Critical Notes for Developers

### DO NOT MODIFY Without Understanding
1. **Voice Feature**: Desktop-only by design (mobile keyboards have voice)
2. **Fallback Logic**: Private messaging works even without database migrations
3. **Message Ordering**: Newest first (reversed from typical chat)
4. **Presence System**: Per-room tracking with 1-minute timeout
5. **Fellowship System**: Complex bidirectional relationships
6. **RLS Policies**: Critical for data security

### Common Pitfalls to Avoid
1. Don't remove `room` columns - breaks entire chat system
2. Don't modify RPC function signatures - causes 400 errors
3. Don't enable voice on mobile - intentionally disabled
4. Don't change message ordering - UX decision for prayer requests
5. Don't skip database migrations - causes missing function errors
6. Don't forget RLS policies - reactions/encouragements won't work without them
7. Don't use 'general' share_type - use 'post' instead (constraint violation)

### Testing Checklist
- [ ] Create journal entry with all fields
- [ ] Share journal to Fellowship (not Community)
- [ ] Create direct post in Fellowship
- [ ] Create direct post in Community Wall
- [ ] Send chat message in each room
- [ ] Toggle message reactions
- [ ] Voice recording (desktop only)
- [ ] Send/accept fellowship request
- [ ] View fellowship feed with journal badges
- [ ] Get AI scripture guidance
- [ ] Anonymous posting
- [ ] Mobile responsive layout

## Support & Resources

**Developer**: Clark Wallace  
**Support**: https://buymeacoffee.com/clarkwallace  
**Issues**: https://github.com/Clark-Wallace/Spiritual-Journey-Journal/issues  
**Live Site**: https://www.spiritualjourney.app

## Version History

- **v2.1.0** (Current): Fellowship privacy separation and enhanced posting
- **v2.0.0**: Complete Svelte rewrite from React Native
- **Stable Commit**: c65bc7f (recommended baseline)
- **Latest Features**: 
  - Journal entries share to Fellowship only with simplified format
  - Direct posting in both Fellowship and Community
  - Working reactions (Pray, Love, Amen) with active states
  - Functional encouragements with inline UI
  - Enhanced Fellowship post creator with character counter
  - Prayer wall aesthetic for Community Wall
  - Debug logging for troubleshooting

## Recent Changes Summary

### Fellowship & Community Separation (Latest)
- Journal entries now share exclusively to Fellowship (private circle)
- Simplified journal sharing: mood shown as "feeling 😊", no gratitude list
- Community Wall for public posts only with sticky notes design
- Both sections support direct posting with different UI styles
- is_fellowship_only flag controls visibility
- Working reactions and encouragements with proper RLS policies
- Enhanced error handling with console debug logging

---

*Last Updated: Current Session*  
*Status: Production Stable with Privacy Enhancement*  
*Next Phase: User feedback and optimization*