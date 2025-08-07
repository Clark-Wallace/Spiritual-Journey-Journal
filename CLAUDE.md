# CLAUDE.md - AI Assistant Context for Spiritual Journey

## Project Overview
Spiritual Journey is a faith-based social platform built with Svelte, TypeScript, and Supabase. It combines personal journaling, community fellowship, real-time chat, and AI-powered biblical guidance.

**Live URL**: https://www.spiritualjourney.app  
**GitHub**: https://github.com/Clark-Wallace/Spiritual-Journey-Journal

## Current Stack & Dependencies
- **Frontend**: Svelte 5.35.5, TypeScript 5.8.3, Vite 7.0.4
- **Backend**: Supabase (PostgreSQL, Auth, Realtime)
- **AI Services**: OpenAI Whisper (voice), Anthropic Claude 3.5 Haiku (guidance)
- **Hosting**: Vercel with automatic deployments
- **Styling**: Custom CSS with Illuminated Sanctuary theme

## Key Features Implemented

### 1. Personal Journaling System
- Mood tracking with 8 spiritual states
- 3-item daily gratitude lists
- Prayer journal with optional saving
- Voice-to-text input (desktop only via Whisper API)
- Collapsible timeline view by date
- Share to community functionality
- Streak tracking for consistency

### 2. Community Fellowship
- Post types: General, Prayer Request, Testimony, Praise
- Anonymous sharing option
- Real-time reactions (Amen, Praying, Love, Hallelujah, Strength)
- Comments/encouragements with live updates
- Prayer warrior commitments
- Compact feed with "Read more" expansion
- Filter by post type or "My Posts"

### 3. The Way - Chat System
- 5 themed rooms: Fellowship Hall, Prayer Chamber, Scripture Study, Testimony, Debate Room
- Real-time messaging with newest first
- Per-room presence tracking
- User status options (Walking in faith, In prayer, Reading Word, Away)
- Message reactions with toggle functionality
- Voice input for desktop users
- Full-screen mobile experience

### 4. AI Scripture Guidance
- Dual mode: AI-powered (Claude) or keyword matching
- Context-aware using journal entries and mood
- Beautiful popup modal display
- 2-3 verses with personal application
- Voice input for situations
- Living Scrolls library (43 scripture compilations)

### 5. Voice Features
- OpenAI Whisper API integration
- Available in: journal, prayer, chat, guidance
- 60-second max recording
- Visual feedback during recording/transcription
- Desktop only (mobile uses native keyboard voice)

## Database Schema

### Core Tables
- `journal_entries`: Personal journal data
- `community_posts`: Shared content
- `chat_messages`: Room-based chat with `room` column
- `user_presence`: Room-specific presence with `room` column
- `chat_reactions`: Message reactions
- `encouragements`: Post comments
- `reactions`: Post reactions
- `prayer_wall`: Prayer requests
- `prayer_warriors`: Prayer commitments

### Important SQL Updates
```sql
-- Add room column to chat_messages
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS room VARCHAR(50) DEFAULT 'fellowship';

-- Add room column to user_presence  
ALTER TABLE user_presence ADD COLUMN IF NOT EXISTS room VARCHAR(50) DEFAULT 'fellowship';

-- Add prayer column to journal_entries
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS prayer TEXT;

-- Enable realtime for chat_reactions
ALTER PUBLICATION supabase_realtime ADD TABLE chat_reactions;
```

## Environment Variables

### Development (.env)
```
VITE_SUPABASE_URL=https://zzociwrszcgrjenqqusp.supabase.co
VITE_SUPABASE_ANON_KEY=[anon-key]
OPENAI_API_KEY=[your-key]
ANTHROPIC_API_KEY=[your-key]
```

### Production (Vercel)
- `OPENAI_API_KEY`: For Whisper voice transcription
- `ANTHROPIC_API_KEY`: For Claude scripture guidance

## Common Commands
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm install          # Install dependencies
git push            # Auto-deploys to Vercel
```

## API Endpoints (Vercel Functions)
- `/api/transcribe`: Whisper voice-to-text
- `/api/guidance`: Claude AI scripture guidance

## Known Issues & Solutions

### Voice Not Working
- Check OPENAI_API_KEY in environment
- Ensure using desktop browser (mobile disabled intentionally)
- Verify microphone permissions

### Chat Messages Not Sending
- Ensure `room` column exists in chat_messages table
- Check user authentication status

### Reactions Not Toggling
- Run chat_reactions realtime SQL
- Verify RLS policies are correct

### Journal Not Saving
- Ensure `prayer` column exists in journal_entries
- Check Supabase connection

## UI/UX Patterns

### Theme: Illuminated Sanctuary
- Dark background (#0a0a0f)
- Golden accents (#ffd700)
- Purple highlights (#8a2be2)
- Divine light ray animations
- Cathedral-inspired borders

### Component Naming
- `*Illuminated.svelte`: Themed components
- `*Compact.svelte`: Space-efficient versions
- `*Collapsible.svelte`: Expandable content

### State Management
- Svelte stores in `/lib/stores`
- localStorage for view persistence
- Real-time subscriptions for live data

## Testing Checklist
- [ ] Journal entry saves with mood, gratitude, content, prayer
- [ ] Share to community works with correct post type
- [ ] Chat messages appear in correct room
- [ ] Reactions toggle on/off properly
- [ ] Voice recording works on desktop
- [ ] AI guidance returns relevant scriptures
- [ ] Mobile layout is responsive
- [ ] Real-time updates work across tabs

## Future Features (Not Implemented)
- Anti-troll moderation tools
- Prayer reminder notifications
- PDF export for journals
- Group prayer circles
- Multi-language support
- Mobile app (React Native)

## Deployment Process
1. Code pushed to GitHub main branch
2. Vercel automatically builds and deploys
3. Custom domain: www.spiritualjourney.app
4. SSL handled by Vercel

## Support Information
- Developer: Clark Wallace
- Buy Me a Coffee: https://buymeacoffee.com/clarkwallace
- Issues: GitHub repository

## Important Notes for AI Assistants

### Always Preserve
- Illuminated Sanctuary theme styling
- Real-time subscription logic
- Voice feature desktop-only design
- Current database schema
- Environment variable structure

### Never Change Without Permission
- Supabase connection details
- API endpoint URLs
- Database table names
- Authentication flow
- Theme color variables

### Common User Requests
1. "Add feature X" - Check if it conflicts with existing features
2. "Fix Y not working" - Usually database column or RLS issue
3. "Change theme" - Preserve CSS variable structure
4. "Add voice to mobile" - Explain why it's desktop-only

### Code Style Guidelines
- Use TypeScript for new components
- Follow existing Svelte patterns
- Maintain consistent CSS variable usage
- Add comments for complex logic
- Test real-time features thoroughly

## Session Context
This app was rebuilt from React Native to Svelte in a continuous development session. Major milestones included:
1. Initial Svelte setup with Supabase
2. Illuminated Sanctuary theme implementation  
3. Chat room system with presence
4. AI scripture guidance integration
5. Voice-to-text feature addition
6. Community features enhancement
7. Mobile responsiveness fixes

The app is now feature-complete for MVP with all core functionality working.

---

*Last Updated: Current Session*  
*Version: 2.0.0*  
*Status: Production Ready*