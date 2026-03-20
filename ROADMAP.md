# SmartSSH Roadmap

This roadmap is ordered by product impact and competitive necessity against Termius.

## Phase 1: Core SSH Parity

1. Real interactive terminal sessions
   - Replace one-shot command execution with a persistent PTY-backed shell
   - Stream stdin/stdout instead of waiting for command completion
   - Support interactive tools such as `vim`, `top`, `htop`, and `tmux`
   - Handle terminal resizing and improve keyboard controls

2. Port forwarding
   - Local port forwarding first
   - Save tunnel definitions per host
   - Show tunnel lifecycle and errors in the UI

3. Jump host and proxy support
   - Bastion / jump host routing
   - SOCKS and HTTP proxy support
   - Route-aware connection testing

4. Session reliability
   - Keepalives
   - Safe reconnect behavior
   - Better background / disconnect handling

## Phase 2: Daily Workflow Features

1. Snippets as executable workflows
   - Insert directly into the terminal
   - Run on the current host
   - Parameterized snippets
   - Organize by host, group, and tag

2. Tabs and split sessions
   - Multiple live sessions
   - Session switcher
   - Split view on larger devices

3. Global command history
   - Per-host and global history
   - Search, favorite, re-run, and edit

4. Better import / export
   - Import from `ssh_config`
   - CSV import
   - Better operational backups

## Phase 3: Security and Admin Credibility

1. Key management improvements
   - Passphrase-protected private keys
   - File-based key import
   - Better biometric protection

2. Known hosts management UI
   - Inspect trusted fingerprints
   - Reset or remove entries
   - Explain mismatches clearly

3. Advanced authentication
   - Agent forwarding
   - FIDO2 / hardware key exploration
   - Better keyboard-interactive UX

4. Auditability
   - Session logs
   - Exportable command history
   - Redaction controls

## Phase 4: Differentiation

1. AI features after shell parity
   - Explain commands
   - Explain error output
   - Generate snippets
   - Suggest safe next commands

2. Infrastructure integrations
   - AWS EC2 inventory
   - DigitalOcean inventory
   - Azure inventory

3. Team features
   - Shared vaults
   - Shared hosts and snippets
   - Permissions and audit logs

## Current Implementation Focus

In progress:
- Phase 1.2 port forward persistence and host routing configuration
- Phase 1.3 jump host and proxy configuration
- Phase 1.4 session reliability improvements
