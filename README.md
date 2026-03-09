# SSH Terminal - iOS SSH Client

A modern, native iOS SSH client that's better than Termius.

## Features (Planned)

### Phase 1: MVP
- [x] Project setup
- [ ] SSH connection
- [ ] Host management
- [ ] Terminal emulator
- [ ] Key management
- [ ] SFTP browser

### Phase 2: Differentiation
- [ ] AI command suggestions
- [ ] AI error diagnosis
- [ ] iCloud sync (free!)
- [ ] Snippets + AI generation
- [ ] Themes

### Phase 3: Business
- [ ] Subscription system
- [ ] Team features
- [ ] Audit logs
- [ ] Web dashboard

## Why Better Than Termius?

| Feature | Termius | SSH Terminal |
|---------|---------|--------------|
| Price | $10/month | $4.99/month or $49/year |
| Cloud Sync | Paid only | Free (iCloud) |
| AI Features | None | Command suggestions, error diagnosis |
| Native Performance | Electron | Swift (fast!) |

## Tech Stack

- **UI**: SwiftUI
- **SSH**: libssh2 / NMSSH
- **Terminal**: SwiftTerm
- **Storage**: Core Data + iCloud
- **AI**: OpenAI API

## Getting Started

```bash
# Open in Xcode
open SmartSSH.xcodeproj
```

## Pricing Strategy

- **Free**: SSH + local storage + basic features
- **Pro ($4.99/mo or $49/yr)**: iCloud sync + AI + themes
- **Team ($9.99/user/mo)**: Shared hosts + audit logs + permissions
