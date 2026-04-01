# Implementation Plan: Bulletproof Process Management & IPv6 Support

The recurring "Address already in use" error and UI desync suggest that the app's internal state is becoming disconnected from the actual `tpws` process state. Additionally, we need to add IPv6 support to prevent bypasses when the user's connection uses v6.

## User Review Required

> [!IMPORTANT]
> **IPv6 Support**: This will modify your system firewall (PF) to also redirect IPv6 traffic on ports 80/443. This is essential because many modern ISPs prioritize IPv6, which currently bypasses the Zapret engine.
> **Stuck Processes**: My previous attempts to fix this via terminal commands might have left several "sudo" prompts waiting in your background terminals. This plan will provide a definitive "Hard Reset" command to clear them.

## Proposed Changes

### 1. 🛡️ Wrapper & PF Upgrade (wrapper.sh)

- **IPv6 Support**:
  - Create `zapret-v6` anchor with `inet6` redirect rules.
  - Update `tpws` to bind to both `127.0.0.1` and `::1`.
  - Block QUIC (UDP 443) for IPv6 as well.
- **Process Management**:
  - Add a `status` command that returns `0` if `tpws` is listening on port 988, and `1` otherwise.
  - Ensure `stop` is even more aggressive in verifying the process is gone.

#### [MODIFY] [wrapper.sh](file:///Users/redpikachu/Projects/Zapret2Mac/Resources/wrapper.sh)

### 2. ⚡ UI & Logic Upgrade (main.swift)

- **Real-time Status**: Implement a background timer that uses `wrapper.sh status` to keep the UI in sync with the actual process.
- **Improved Switch**: Use the new `restart` command for all strategy changes to ensure a clean state.
- **SOCKS5 IPv6**: (Optional but recommended) Update SOCKS5 proxy to also bind to `::1`.

#### [MODIFY] [main.swift](file:///Users/redpikachu/Projects/Zapret2Mac/main.swift)

### 3. 🧹 Repository Cleanup

- Final push of the cleaned-up source code to your public GitHub.

## Verification Plan

### Automated Tests

- Run `sudo pfctl -a zapret-v6 -s rules` to verify IPv6 redirection.
- Run `lsof -i :988` to ensure `tpws` is listening on both `127.0.0.1` and `::1`.
- Run `wrapper.sh status` after starting/stopping.

### Manual Verification

- Verify that clicking "Start" in the app menu works first time.
- Check if YouTube/Discord works on an IPv6 connection.

