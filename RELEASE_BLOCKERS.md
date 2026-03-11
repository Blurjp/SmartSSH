# Release Blockers

## P0 - Must fix before any production release

- Replace mocked SSH with a real SSH transport in `SmartSSH/Services/SSHClient.swift` and `SmartSSH/Services/SSHManager.swift`.
- Replace mocked SFTP with a real remote file implementation in `SmartSSH/Services/SFTPClient.swift` and finish download support in `SmartSSH/Views/SFTPView.swift`.
- Replace simulated AI responses with a real backend integration or remove AI from the shipped product surface in `SmartSSH/Services/AIService.swift`.
- Generate valid SSH-compatible keys and keep private keys out of `UserDefaults` in `SmartSSH/Services/SSHManager.swift`.
- Fix launch/test stability and restore a passing UI smoke suite in `SmartSSHUITests/SmartSSHUITests.swift`.
- Add the missing app icon assets referenced by `SmartSSH/Assets.xcassets/AppIcon.appiconset/Contents.json`.

## P1 - High priority product and security fixes

- Delete saved credentials when hosts are deleted or connection tests create temporary hosts.
- Persist user-created keys and snippets across launches.
- Enforce subscription gating for paid features in the app shell.
- Remove placeholder settings flows and placeholder public links.
- Deduplicate subscription state refreshes.

## P2 - Quality and UX follow-ups

- Fix terminal auto-scroll behavior.
- Improve error handling and user-facing messaging for file operations and settings actions.
- Add targeted unit or UI coverage for host creation, key persistence, snippet persistence, and subscription gating.
