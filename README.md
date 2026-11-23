# sshid-sync

Fetches the SSH public keys of one or more [sshid.io](https://sshid.io) users and adds them to `/root/.ssh/authorized_keys` automatically.

- Keys that are already present are **not added twice** (the comparison uses the key itself, the comment does not matter).
- Invalid responses (e.g. HTML error pages) are ignored: only real public keys end up in the file.
- If sshid.io is unreachable, the file is left unchanged.
- The sync runs regularly (default: every 4 hours) and shortly after every boot.

## Installation

```bash
git clone https://github.com/REPO_OWNER/sshid-sync.git
cd sshid-sync
sudo ./install.sh
```

Or as a one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/sshid-sync/main/install.sh | sudo bash
```

The installer asks for:

1. the **sshid.io usernames**: one per prompt, an empty input ends the list. Each name is checked immediately to see whether sshid.io returns keys for it, and which ones.
2. the **interval** in hours (default: 4)

It then creates a backup of `authorized_keys`, sets up the schedule (systemd timer, otherwise cron) and runs the first sync.

### Non-interactive

```bash
sudo ./install.sh --users okaluk,colleague --interval 4 -y
```

## Usage

| Task | Command |
|---|---|
| Sync now | `sudo sshid-sync` |
| Add/remove users | Edit `/etc/sshid-sync.conf` or run `sudo ./install.sh` again |
| View the log | `journalctl -t sshid-sync` |
| Check the schedule (systemd) | `systemctl list-timers sshid-sync.timer` |
| Uninstall | `sudo ./install.sh --uninstall` |

`/etc/sshid-sync.conf` contains one username per line, comments start with `#`:

```
okaluk
# colleague
```

## What gets installed

| File | Purpose |
|---|---|
| `/usr/local/sbin/sshid-sync` | Sync script |
| `/etc/sshid-sync.conf` | List of sshid.io users |
| `/etc/systemd/system/sshid-sync.{service,timer}` | Schedule (with systemd) |
| `/etc/cron.d/sshid-sync` | Schedule (without systemd) |
| `/root/.ssh/authorized_keys.bak-*` | Backup taken before installation |

## Important

- **Every configured sshid.io user gets root access.** The same applies to anyone who takes over one of those sshid.io accounts, so protect the accounts well (passkey/2FA).
- **Keys are only added, never removed.** If you remove a device on sshid.io or a user from the configuration, you have to delete that key from `authorized_keys` yourself. The log (`journalctl -t sshid-sync`) records the user and the fingerprint for every key that was added.
- Keep at least one key in `authorized_keys` that does not depend on sshid.io.

## Requirements

`bash`, `curl`, `ssh-keygen` (openssh-client), `logger`, and either systemd or cron. On Debian/Ubuntu these are usually already present.

## License

MIT
