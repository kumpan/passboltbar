# PassboltBar

Your Passbolt passwords in the Mac menu bar. Press **⌃⌥P**, type a few letters, press **↩**, and the
password is on your clipboard. The clipboard clears itself after 30 seconds.

PassboltBar is a small front end for the official
[Passbolt CLI](https://github.com/passbolt/go-passbolt-cli). It does no encryption and no network requests
to Passbolt itself; the CLI does that.

**Requires** macOS 14 or later, and a Passbolt account.

---

## Install

### 1. Install the Passbolt CLI

In Terminal (Homebrew required, see [brew.sh](https://brew.sh)):

```sh
brew install passbolt/tap/go-passbolt-cli
```

### 2. Connect the CLI to your Passbolt account

1. In the Passbolt browser extension, click your avatar → **Manage account** → **Keys inspector**
   → **Private key** to download your private key.
2. Run this in Terminal, replacing the server address and file name with yours:

   ```sh
   passbolt configure --serverAddress https://passbolt.example.com --userPrivateKeyFile ~/Downloads/passbolt_private.txt
   ```

   The command prints nothing when it succeeds.
3. Delete the downloaded key file. The CLI has made its own copy.

### 3. Install the app

1. Download **`PassboltBar-<version>.zip`** from the
   **[latest release](https://github.com/kumpan/passboltbar/releases/latest)** (under **Assets**).
2. Unzip it and drag **PassboltBar** into your **Applications** folder.
3. Open it. A purple key appears in the menu bar. The app is signed and notarized by Apple, so it opens
   without warnings.

### 4. First launch

1. **Passphrase:** enter your Passbolt passphrase, the one you use to unlock the browser extension. It is
   saved in your Mac's Keychain and unlocked with Touch ID.
2. **Two-factor login (if your account uses it):** click **Scan with Camera** and allow camera access.
   On your phone, in **Google Authenticator**, tap ☰ → **Transfer accounts** → **Export accounts**,
   select **only Passbolt**, tap **Next**, and hold the QR code up to your Mac's camera. Your phone keeps
   working as before. With another authenticator app, choose **Paste a setup key instead**.
3. If macOS asks whether PassboltBar may use information in your Keychain, enter your Mac password and
   click **Always Allow**.

**Start at login (recommended):** System Settings → General → Login Items & Extensions → **Open at
Login** → **+** → choose PassboltBar.

---

## Using it

| Key | Action |
|---|---|
| **⌃⌥P** | Open or close PassboltBar from anywhere |
| Type | Search by name, username or website |
| **↑ / ↓** | Move the selection |
| **↩** | Copy the password (cleared from the clipboard after 30 s) |
| **⌘↩** | Copy the username |
| **→** | Show every field: URLs, description, note and custom fields. **↩** copies the selected one, **←** goes back |

- **+** adds a new password. The wand button generates a strong one.
- **⚙︎** opens Settings: clipboard clear time, updates, and removing the saved passphrase or 2FA secret.
- Touch ID is asked for at most every 5 minutes.

## Updates

PassboltBar checks for new versions once a day. When one is available, **Update x.y.z** appears at
the bottom of the window. Click it, then **Install and Relaunch**. You can also go to Settings →
**Check for Updates**. Updates are only installed if they are signed by Kumpan and notarized by Apple.

## Troubleshooting

| Problem | Fix |
|---|---|
| "passbolt CLI not found" | Install the CLI (step 1). If it lives somewhere unusual, set its path in Settings. |
| "Wrong passphrase" | Enter it again. It's the passphrase for the browser extension, not your Mac password. |
| Two-factor login failed | Settings → **Forget TOTP secret**, then scan the QR code again. |
| The camera shows nothing | System Settings → Privacy & Security → Camera → turn on PassboltBar. |
| Repeated Keychain password prompts | Click **Always Allow** rather than **Allow**. If they continue: Settings → Forget passphrase and TOTP secret, then set them up again. |
| ⌃⌥P does nothing | Click the menu bar icon instead, and tell us your macOS version. |

## Privacy and security

- Your passphrase and 2FA secret stay in your Mac's Keychain, and reading them requires Touch ID. They are
  never written to disk or shown on the command line.
- Passwords are fetched only when you copy them, and are never stored. Copied passwords are hidden from
  clipboard-history apps and cleared after 30 seconds.
- Trade-off: storing the 2FA secret on your Mac means this Mac plus Touch ID covers both login factors.

---

<details>
<summary><b>For developers</b></summary>

```sh
swift test                  # unit tests
./build.sh                  # → dist/PassboltBar.app (Developer ID-signed if the cert is installed, else ad-hoc)
./build.sh release          # also notarizes + staples → dist/PassboltBar-<VERSION>.zip
swift scripts/make-icon.swift preview out.png   # icon variants; `… make-icon.swift 3` writes Resources/AppIcon.icns
```

- **Releases:** every push to `main` that isn't docs-only runs `.github/workflows/release.yml`: tests,
  build, Developer ID signing, notarization, and a GitHub release `v<VERSION>.<run number>`. Edit
  `VERSION` to bump the major/minor version. The workflow header lists the four secrets it needs.
- **Local releases** need Kumpan's *Developer ID Application* certificate in the login keychain and a
  notarytool profile:
  `xcrun notarytool store-credentials PassboltBar --apple-id <apple id> --team-id NH4M8452G6`.
- **Implementation notes:**
  - The passphrase and TOTP secret reach the CLI only via the child environment (`USERPASSWORD`,
    `MFAMODE=noninteractive-totp`, `MFATOTPTOKEN`). The CLI's stdin is `/dev/null`, so prompts fail fast
    instead of hanging.
  - `create` passes the new password as `--password`, because the CLI can't read it from stdin. It is
    briefly visible in `ps`.
  - ⌃⌥P uses private AppKit API to open `MenuBarExtra` on macOS 27, where the button has no action.
    If that API goes away, the hotkey becomes a no-op; clicking the icon still works.
  - The updater verifies the code signature requirement (team `NH4M8452G6`, id `se.kumpan.passboltbar`)
    and `spctl` notarization before swapping the bundle.

</details>
