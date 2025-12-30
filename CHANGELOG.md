# Changelog

All notable changes to Buds will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2025-12-30

### 🎉 Initial Beta Release (Phase 10.1)

First TestFlight beta release! Track your cannabis journey with privacy-first memory organization.

### Added

#### Core Features
- **Jar Organization** - Organize memories into "jars" (solo or shared collections)
  - Solo jar created automatically on first launch
  - Create custom jars with names and colors
  - Move memories between jars
  - Delete jars (memories move to Solo jar)
  - Edit jar names and colors

- **Memory Management** - Track your cannabis experiences
  - Simplified create flow (strain name + product type + images)
  - Enrich memories with detailed info (rating, effects, flavors, notes, method, etc.)
  - Edit memories to add or update details
  - Delete memories with confirmation
  - Add up to 5 images per memory
  - Image carousel view in detail screen

- **Reactions** - React to memories with emoji (5 types)
  - Heart ❤️, Fire 🔥, Laughing 😂, Mind Blown 🤯, Chilled 😌
  - Toggle reactions on/off
  - See reaction counts
  - Works in both solo and shared jars

- **Onboarding** - First-launch tutorial
  - 3 screens explaining jars, buds, and E2EE privacy
  - Skip button on all screens
  - Never shows again after completion

- **Profile & Settings**
  - Phone number authentication via Google Sign-In
  - Privacy documentation links
  - Sign out functionality

#### Technical
- **E2EE Foundation** - End-to-end encryption for shared jars (not yet enabled)
  - TOFU (Trust On First Use) device pinning
  - Ed25519 signatures
  - ChaCha20-Poly1305 encryption
- **Local-First Storage** - SQLite database with receipt-based architecture
- **Image Storage** - Efficient blob storage in database
- **Background Sync** - Inbox polling for future sharing features

### Design System

- **Color Palette** - Forest premium aesthetic (#1B4332 primary, #3D2645 purple)
  - Full dark mode support
  - Semantic color system
- **Typography** - Clear hierarchy with SF Pro
- **Spacing** - Consistent 4-48pt scale
- **Components** - Reusable buttons, cards, tags, fields

### Known Limitations

- **Single Device Only** - Data stored locally, no sync between devices yet
- **No Multi-User Sharing** - Shared jars exist but E2EE sharing not enabled
- **No Backup** - Data lives on device only (export/import coming soon)
- **iOS Only** - iPhone app only (web/Android in future)

### What's Next (Post-Beta)

- Multi-device sync with E2EE
- Share memories to jars with friends
- Cloud backup to R2 storage
- Map view for dispensary visits
- Shop integration
- AI-powered recommendations

---

## Future Releases

See `/docs/planning/R1_MASTER_PLAN.md` for roadmap.

---

**Note**: This is a beta release. Data is stored locally. Please report bugs via TestFlight feedback!
