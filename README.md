# sshid-sync

Holt die SSH-Public-Keys eines oder mehrerer [sshid.io](https://sshid.io)-Benutzer und trägt sie automatisch in `/root/.ssh/authorized_keys` ein.

- Bereits vorhandene Keys werden **nicht doppelt** eingetragen (Vergleich über den Schlüssel selbst, der Kommentar spielt keine Rolle).
- Ungültige Antworten (z. B. HTML-Fehlerseiten) werden ignoriert: Es landen nur echte Public Keys in der Datei.
- Ist sshid.io nicht erreichbar, bleibt die Datei unverändert.
- Der Abgleich läuft regelmäßig (Standard: alle 4 Stunden) und kurz nach jedem Systemstart.

## Installation

```bash
git clone https://github.com/REPO_OWNER/sshid-sync.git
cd sshid-sync
sudo ./install.sh
```

Oder in einer Zeile:

```bash
curl -fsSL https://raw.githubusercontent.com/REPO_OWNER/sshid-sync/main/install.sh | sudo bash
```

Der Installer fragt nach:

1. den **sshid.io-Benutzernamen**: einer pro Eingabe, leere Eingabe beendet die Liste. Für jeden Namen wird sofort geprüft, ob und welche Keys sshid.io liefert.
2. dem **Intervall** in Stunden (Standard: 4)

Danach legt er ein Backup der `authorized_keys` an, richtet den Zeitplan ein (systemd-Timer, sonst Cron) und führt den ersten Abgleich aus.

### Ohne Rückfragen

```bash
sudo ./install.sh --users okaluk,kollege --interval 4 -y
```

## Benutzung

| Aufgabe | Befehl |
|---|---|
| Sofort abgleichen | `sudo sshid-sync` |
| Benutzer hinzufügen/entfernen | `/etc/sshid-sync.conf` bearbeiten oder `sudo ./install.sh` erneut ausführen |
| Log ansehen | `journalctl -t sshid-sync` |
| Zeitplan prüfen (systemd) | `systemctl list-timers sshid-sync.timer` |
| Deinstallieren | `sudo ./install.sh --uninstall` |

`/etc/sshid-sync.conf` enthält einen Benutzernamen pro Zeile, Kommentare beginnen mit `#`:

```
okaluk
# kollege
```

## Was installiert wird

| Datei | Zweck |
|---|---|
| `/usr/local/sbin/sshid-sync` | Sync-Skript |
| `/etc/sshid-sync.conf` | Liste der sshid.io-Benutzer |
| `/etc/systemd/system/sshid-sync.{service,timer}` | Zeitplan (bei systemd) |
| `/etc/cron.d/sshid-sync` | Zeitplan (ohne systemd) |
| `/root/.ssh/authorized_keys.bak-*` | Backup vor der Installation |

## Wichtig

- **Jeder eingetragene sshid.io-Benutzer erhält Root-Zugang.** Dasselbe gilt für jeden, der eines dieser sshid.io-Konten übernimmt. Schütze die Konten deshalb gut (Passkey/2FA).
- **Keys werden nur hinzugefügt, nie entfernt.** Entfernst du ein Gerät bei sshid.io oder einen Benutzer aus der Konfiguration, musst du dessen Key selbst aus `authorized_keys` löschen. Im Log (`journalctl -t sshid-sync`) steht bei jedem hinzugefügten Key der Benutzer und der Fingerprint.
- Behalte mindestens einen Key fest in `authorized_keys`, der nicht von sshid.io abhängt.

## Voraussetzungen

`bash`, `curl`, `ssh-keygen` (openssh-client), `logger` sowie systemd oder cron. Auf Debian/Ubuntu ist das in der Regel vorhanden.

## Lizenz

MIT
