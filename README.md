# 🕊️ Spiritual Journey - A Faith-Based Social Platform

A modern web application for spiritual growth, Christian fellowship, and AI-powered biblical guidance. Built with love, faith, and cutting-edge technology.

**Live at:** [www.spiritualjourney.app](https://www.spiritualjourney.app)

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/clarkwallace)

## ✨ Overview

Spiritual Journey is a comprehensive platform that combines personal journaling, community fellowship, real-time chat, and AI-powered scripture guidance to support your walk with faith. The app features a beautiful "Illuminated Sanctuary" theme inspired by cathedral architecture with golden accents and divine lighting effects.

## 🙏 Key Features

### 📔 Personal Journaling
- **Mood Tracking**: Track your emotional and spiritual state (grateful, peaceful, joyful, hopeful, reflective, troubled, anxious, seeking)
- **Gratitude Lists**: Daily gratitude practice with 3 items
- **Prayer Journal**: Private space for prayers with optional saving
- **Voice-to-Text**: Speak your thoughts and prayers (desktop - uses OpenAI Whisper)
- **Collapsible Timeline**: Journal entries organized by date
- **Streak Tracking**: Monitor your consistency in journaling

### 🌍 Community Fellowship
- **Share Your Journey**: Optionally share journal entries with the community
- **Post Types**: 
  - Regular posts
  - Prayer requests (with urgent flag)
  - Testimonies
  - Praise reports
- **Anonymous Sharing**: Share while maintaining privacy
- **Real-time Interactions**: 
  - Reactions: Amen 🙏, Praying 🤲, Hallelujah 🎉, Love ❤️, Strength 💪
  - Comments and encouragements with real-time updates
  - Prayer warrior commitments for prayer requests
- **Smart Feed**: Compact, social media-style layout with "Read more" expansion

### 💬 The Way - Live Chat Rooms
Five themed chat rooms for different types of fellowship:
- **Fellowship Hall** ⛪: General Christian community chat
- **Prayer Chamber** 🙏: Dedicated prayer requests and intercession
- **Scripture Study** 📖: Bible discussion and verse sharing
- **Testimony** ✨: Share what God has done in your life
- **Debate Room** ⚖️: Respectful theological discussions with rules of engagement

Features:
- Real-time messaging with newest messages at top
- Live presence indicators showing who's in each room
- User status options: Walking in faith, In prayer, Reading Word, Away
- Message reactions with toggle functionality
- Voice-to-text input (desktop only)
- Per-room presence tracking
- Mobile responsive full-screen experience

### ✨ AI-Powered Scripture Guidance
- **Two Modes**: 
  - AI-Powered (Claude 3.5 Haiku) for personalized guidance
  - Keyword matching for quick scripture lookup
- **Context-Aware**: Considers recent journal entries and current mood
- **Beautiful Modal Display**: 
  - 2-3 relevant Bible verses
  - Personal application for each verse
  - Encouraging message
- **Voice Input**: Speak your situation for guidance
- **Living Scrolls Library**: 43 pre-compiled scripture collections for life situations

### 🎤 Voice Features (Desktop Only)
- Powered by OpenAI Whisper API
- Available in:
  - Journal content and prayer sections
  - Chat messages in The Way
  - Scripture guidance input
- Mobile users use native keyboard voice input
- 60-second maximum recording duration

### 🎨 Illuminated Sanctuary Theme
- Cathedral-inspired design with golden accents
- Divine light rays animation effects
- Stained glass color palette
- CSS variables for consistent theming
- Smooth animations and transitions
- Fully responsive for mobile and desktop
- Dark background with luminous elements

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ 
- npm or yarn
- Supabase account (free tier works)
- Vercel account (for deployment)
- OpenAI API key (for voice features)
- Anthropic API key (for AI guidance)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/Clark-Wallace/Spiritual-Journey-Journal.git
cd svelte-app
```

2. Install dependencies:
```bash
npm install
```

3. Set up environment variables:
Create a `.env` file with:
```env
# Supabase Configuration
VITE_SUPABASE_URL=your-supabase-url
VITE_SUPABASE_ANON_KEY=your-supabase-anon-key

# For AI Features (Vercel Functions)
OPENAI_API_KEY=your-openai-api-key
ANTHROPIC_API_KEY=your-anthropic-api-key
```

4. Run the development server:
```bash
npm run dev
```

Visit `http://localhost:5173`

## 📦 Database Setup

Run these SQL scripts in your Supabase SQL editor in order:

1. **Core Tables**: `supabase/schema.sql`
   - journal_entries, user_profiles, daily_verses
2. **Social Features**: `supabase/social-schema.sql`
   - community_posts, encouragements, reactions, prayer_wall
3. **Chat System**: `supabase/chat-schema.sql`
   - chat_messages, user_presence, chat_reactions
4. **Real-time**: `supabase/enable-realtime.sql`
   - Enables real-time subscriptions for all tables
5. **Chat Reactions**: `supabase/enable-chat-reactions-realtime.sql`
   - Enables real-time for chat reactions
6. **Additional Updates**: Run any SQL files for room columns and presence tracking

## 🚢 Deployment

### Vercel Deployment

1. Push to GitHub
2. Import repository in Vercel
3. Add environment variables in Vercel dashboard:
   - `OPENAI_API_KEY` (for voice transcription)
   - `ANTHROPIC_API_KEY` (for scripture guidance)
4. Deploy! Vercel will auto-deploy on push to main

### Custom Domain Setup
1. Add domain in Vercel project settings
2. Update DNS records with your provider:
   - A record pointing to Vercel
   - CNAME for www subdomain
3. SSL certificates are automatic

## 🛠️ Tech Stack

- **Frontend**: 
  - Svelte 5 (latest version)
  - TypeScript for type safety
  - Vite for fast builds
- **Backend**: 
  - Supabase (PostgreSQL database)
  - Supabase Auth (authentication)
  - Supabase Realtime (WebSocket subscriptions)
- **AI/ML**: 
  - OpenAI Whisper API (voice transcription)
  - Anthropic Claude 3.5 Haiku (scripture guidance)
- **Hosting**: 
  - Vercel (automatic CI/CD)
  - Vercel Functions (serverless API)
- **Styling**: 
  - Custom CSS with CSS Variables
  - Illuminated Sanctuary theme
  - Mobile-first responsive design

## 📁 Project Structure

```
svelte-app/
├── api/                    # Vercel serverless functions
│   ├── guidance.js        # Claude AI scripture guidance
│   └── transcribe.js      # Whisper voice transcription
├── src/
│   ├── lib/
│   │   ├── components/    # Svelte components
│   │   │   ├── *Illuminated.svelte  # Themed components
│   │   │   ├── VoiceRecorder.svelte # Voice input
│   │   │   └── ScriptureGuide.svelte # AI guidance
│   │   ├── stores/        # State management
│   │   ├── supabase.ts    # Database client
│   │   └── types.ts       # TypeScript types
│   ├── App.svelte         # Main app component
│   └── main.ts           # App entry point
├── supabase/             # Database schemas
├── public/               # Static assets
└── package.json         # Dependencies
```

## 📱 Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+
- Mobile browsers (iOS Safari, Chrome Mobile)

## 🔒 Security Features

- Row Level Security (RLS) on all tables
- Anonymous posting options
- Secure authentication via Supabase Auth
- API keys stored in environment variables
- HTTPS enforced on production

## 🤝 Contributing

We welcome contributions that align with the app's faith-based mission! 

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 💝 Support Development

If this app has blessed you, consider supporting development:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/clarkwallace)

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙌 Acknowledgments

- Built with faith and love for the Christian community
- Inspired by the need for a modern, safe space for spiritual growth
- Scripture quotations from public domain translations
- Living Scrolls compilation for biblical guidance
- Special thanks to all beta testers and prayer warriors

## 📞 Contact & Support

- **Developer**: Clark Wallace
- **Website**: [www.spiritualjourney.app](https://www.spiritualjourney.app)
- **Buy Me A Coffee**: [buymeacoffee.com/clarkwallace](https://buymeacoffee.com/clarkwallace)
- **Issues**: Create an issue on GitHub

## 🚀 Future Roadmap

- [ ] Mobile app (React Native)
- [ ] Prayer reminder notifications
- [ ] Group prayer circles
- [ ] Daily devotional content
- [ ] Scripture memorization tools
- [ ] Export journal entries as PDF
- [ ] Multi-language support
- [ ] Advanced moderation tools

---

*"For I know the plans I have for you," declares the Lord, "plans to prosper you and not to harm you, plans to give you hope and a future." - Jeremiah 29:11*

**Made with ❤️ and 🙏 for the glory of God**