# PassboltBar

A macOS menu bar app for searching, copying and adding Passbolt passwords. It is a thin wrapper around the
official [go-passbolt-cli](https://github.com/passbolt/go-passbolt-cli). The app itself does no crypto and
makes no API calls.

## 1. Install the CLI

```sh
brew install passbolt/tap/go-passbolt-cli
```

## 2. Configure the CLI

`passbolt configure` is not interactive; it saves the flags you give it. Don't pass `--userPassword`,
because PassboltBar supplies the passphrase from the Keychain.

```sh
passbolt configure --serverAddress https://passbolt.example.com --userPrivateKeyFile ~/Downloads/passbolt_private.txt
passbolt list resource -c name      # asks for your passphrase; should print your entries
```

Download the private key from the browser extension: **Manage account → Keys inspector → Private key**.
Delete the downloaded file once `list` works, because the key has been copied into
`~/Library/Application Support/go-passbolt-cli/go-passbolt-cli.toml`.

## 3. Build

```sh
./build.sh                          # → dist/PassboltBar.app (Developer ID-signed if the cert is installed, else ad-hoc)
./build.sh release                  # also notarizes + staples → dist/PassboltBar-<VERSION>.zip
swift test                          # unit tests
```

A release needs Kumpan's **Developer ID Application** certificate in the login keychain, and a notarytool
profile named `PassboltBar`, created once with
`xcrun notarytool store-credentials PassboltBar --apple-id <apple id> --team-id NH4M8452G6` and an
app-specific password from account.apple.com.

### Automatic releases

Every push to `main` runs `.github/workflows/release.yml`: tests, build, Developer ID signing, notarization,
and a GitHub release `v<VERSION>.<run number>` with the zip attached. Edit `VERSION` to bump the
major/minor version. The workflow's header lists the four repository secrets it needs.

## Installing (for colleagues)

1. Install and configure the CLI (steps 1–2 above).
2. Download the latest release. The repo is private, so you need to be signed in to GitHub as a member of
   the kumpan organization.
   - In the browser: **[github.com/kumpan/passboltbar/releases/latest](https://github.com/kumpan/passboltbar/releases/latest)**
     → download `PassboltBar-<version>.zip` under **Assets**.
   - Or in Terminal: `gh release download -R kumpan/passboltbar -p 'PassboltBar-*.zip' -D ~/Downloads`
3. Unzip it, move `PassboltBar.app` to **Applications** and open it. It is notarized, so there are no
   Gatekeeper warnings.
4. Enter your passphrase, and scan your authenticator QR code if your account uses TOTP.

To update, download the latest release and replace the app in Applications. Your Keychain entries stay.

## 4. First run

1. Open `dist/PassboltBar.app` (or copy it to `/Applications` first). A key icon appears in the menu bar.
2. Enter your private-key passphrase. It is stored in the login Keychain (service `PassboltBar`).
   Reading it requires Touch ID or your Mac password, and one approval covers the next 5 minutes.
3. Ad-hoc builds only: after each rebuild macOS asks whether PassboltBar may use the Keychain item,
   because an ad-hoc signature changes with every build. Choose **Always Allow**. Developer ID builds keep
   their Keychain access across updates.

**Usage**

| Key | Action |
|---|---|
| ⌃⌥P | Open or close the menu from anywhere |
| ↑ / ↓ | Move the selection |
| ↩ | Copy the password (concealed, cleared after 30 s if still on the clipboard) |
| ⌘↩ | Copy the username |

The **+** button adds a password (the wand icon generates one), and the gear icon opens Settings: CLI
path, clipboard clear time, and forgetting the stored passphrase or TOTP secret.

## 5. Start at login

System Settings → General → Login Items & Extensions → **Open at Login** → **+** → pick `PassboltBar.app`.
Copy it to `/Applications` first so the path stays the same across rebuilds.

## MFA (TOTP)

The CLI logs in fresh on every call, so each call needs a TOTP code. When your account uses TOTP,
PassboltBar asks once for your **TOTP secret** (the base32 key, or the `otpauth://` link in the QR code).
It stores the secret in the Keychain next to the passphrase, behind the same Touch ID prompt, and passes
it to the CLI as `MFAMODE=noninteractive-totp` and `MFATOTPTOKEN` environment variables. Nothing is
written to the CLI config.

Trade-off: this Mac plus Touch ID then covers both factors.

With **Google Authenticator** this takes one scan, and your 2FA setup is left unchanged:
1. In PassboltBar, click **Scan with Camera**. The first time, allow camera access.
2. On your phone, tap ☰ → **Transfer accounts** → **Export accounts**, select **only** Passbolt → **Next**.
3. Hold the QR code up to the Mac's camera. PassboltBar reads it, keeps only the Passbolt secret and
   stops the camera.

PassboltBar also accepts a plain base32 setup key or an `otpauth://` link from other authenticator apps.

## Security notes

- The passphrase and TOTP secret are passed to the CLI only through the child process environment
  (`USERPASSWORD`, `MFATOTPTOKEN`), never on the command line.
- Passwords are fetched on demand and never cached or written to disk. Clipboard entries are marked
  `org.nspasteboard.ConcealedType` and `TransientType`, so clipboard managers skip them.
- The CLI has no stdin option for the password of a new resource. `create` passes it as `--password`, so
  it is visible in `ps` for the second or two the process runs.
- Swift strings can't be reliably wiped from memory. The app releases secrets as soon as they are used
  and zeroes the raw buffers it controls.
- The ⌃⌥P hotkey uses private AppKit API to open the menu, because on macOS 27 SwiftUI's `MenuBarExtra`
  can't be opened programmatically. If a macOS update breaks this, the hotkey stops working (it won't
  crash the app); clicking the icon still works.
