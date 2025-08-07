# Spiritual Journey - Christian Social Network & Prayer App

A faith-based social platform that combines personal spiritual journaling with community fellowship. Built with love using Svelte and Supabase.

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## ✨ Features

### 📔 Personal Spiritual Journal
- Daily devotional entries with mood tracking
- Gratitude lists to count your blessings
- Prayer journaling with optional saving
- Streak tracking for spiritual consistency

### 📖 Living Scrolls Scripture Guidance
- 43 life situations with curated scripture compilations
- Organized into 7 parts covering all aspects of life
- Keyword-based scripture matching
- Biblical wisdom for real-world challenges

### 💬 The Way - Fellowship Chat Room
- Real-time Christian fellowship
- Online presence indicators with status (Online, Away, Praying, Reading Scripture)
- Prayer request highlighting
- Message reactions (Amen, Praying, Love)
- Community guidelines based on biblical principles

### 🌍 Community Features
- Share journal entries as posts, prayers, testimonies, or praise reports
- Community prayer wall with prayer warrior commitments
- Anonymous sharing options for sensitive requests
- Reactions and encouragements system
- Real-time updates across all features

## 🚀 Getting Started

### Prerequisites
- Node.js 18+ 
- npm or yarn
- Supabase account (free tier works great)

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/spiritual-journey.git
cd spiritual-journey/svelte-app
```

2. **Install dependencies**
```bash
npm install
```

3. **Set up environment variables**
```bash
cp .env.example .env
```

Edit `.env` with your Supabase credentials:
```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

4. **Set up Supabase database**

Go to your Supabase SQL Editor and run these scripts in order:

- `/supabase/schema.sql` - Core tables (journal, prayers, verses)
- `/supabase/social-schema.sql` - Community features
- `/supabase/chat-schema.sql` - Chat room tables
- `/supabase/enable-realtime.sql` - Enable real-time subscriptions

5. **Start the development server**
```bash
npm run dev
```

Visit `http://localhost:5173` to see your app!

## 🌐 Deployment

### Deploying to Vercel

1. Push your code to GitHub
2. Connect your GitHub repo to Vercel
3. Add environment variables in Vercel:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
4. Deploy!

### Custom Domain
To use a custom domain like `spiritualjourney.app`:
1. Add domain in Vercel dashboard
2. Update DNS records with your domain provider
3. SSL certificates are automatic

## 📁 Project Structure

```
svelte-app/
├── src/
│   ├── lib/
│   │   ├── components/     # Svelte components
│   │   ├── stores/         # State management
│   │   ├── supabase.ts     # Database client
│   │   ├── types.ts        # TypeScript types
│   │   └── livingScrollsData.ts  # Scripture data
│   ├── App.svelte          # Main app component
│   └── main.ts            # App entry point
├── supabase/              # Database schemas
│   ├── schema.sql         # Core tables
│   ├── social-schema.sql  # Social features
│   ├── chat-schema.sql    # Chat tables
│   └── enable-realtime.sql # Realtime config
├── public/                # Static assets
└── package.json          # Dependencies
```

## 🛠️ Tech Stack

- **Frontend**: Svelte + TypeScript
- **Build Tool**: Vite
- **Database**: Supabase (PostgreSQL)
- **Real-time**: Supabase Realtime
- **Authentication**: Supabase Auth
- **Hosting**: Vercel
- **Styling**: CSS-in-Svelte

## 📱 Features Roadmap

- [ ] Mobile app (React Native)
- [ ] Bible verse of the day API
- [ ] Group prayer circles
- [ ] Daily devotional content
- [ ] Scripture memorization tools
- [ ] Prayer reminder notifications
- [ ] Export journal entries as PDF
- [ ] Dark mode theme

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with love for the Christian community
- Inspired by the need for authentic digital fellowship
- Scripture quotations from public domain translations
- Living Scrolls compilation for biblical guidance

## 💬 Support

For support, questions, or prayer requests:
- Open an issue on GitHub
- Visit [spiritualjourney.app](https://spiritualjourney.app)

---

**"For where two or three gather in my name, there am I with them." - Matthew 18:20**

Made with ❤️ and 🙏 for the glory of God