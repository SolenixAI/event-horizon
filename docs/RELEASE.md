# Release

Versioned macOS releases are built from `main`, using the release date as CalVer
`YYYY.MM.DD` (for example, `2026.11.08`). Bump both version lines in
`Glimmer/Version.xcconfig` and nothing else; the version is not set in
`project.pbxproj`. Every change ships through a PR.

## 1. Branch and build

```bash
git switch main && git pull && git switch -c my-change
# edit; bump Glimmer/Version.xcconfig and add a CHANGELOG entry
make dev     # tests, then build + install + relaunch (notarized when credentials are configured)
```

`make app` is the fast compile-only check. `make dist` builds the notarized DMG
without publishing. Both `dist` and `release-publish` refuse to run against a
dirty worktree, so commit or stash first: a release built from uncommitted
changes would not reproduce from the source at the tag.

## 2. PR and release

```bash
git push -u origin my-change && gh pr create --fill
# merge the PR on GitHub, then tag that version on main:
git switch main && git pull
git tag "$(sed -n 's/^MARKETING_VERSION = //p' Glimmer/Version.xcconfig | tr -d ' ')"
git push origin --tags
```

The `macOS app release` workflow accepts only CalVer tags matching the version
in `Glimmer/Version.xcconfig`, and verifies the tagged commit is on `main`. Set
the repository variable `NOTARIZED_RELEASE_ENABLED=true` only after the
protected `release` environment contains the secrets below. The workflow then
builds and signs the app, notarizes and staples both the app and DMG, checks
Gatekeeper acceptance, creates SHA-256 checksums, EdDSA-signs the Sparkle ZIP,
and publishes the release plus update metadata.

When the maintainer has only an Apple Development certificate, use
`make release-publish-dev` from a clean checkout on the maintainer Mac. It signs
the app, builds a DMG, validates the code signature and Sparkle update
signature, and publishes the GitHub release and update feed. **This does not
notarize the app. Gatekeeper may block fresh downloads; users may need to
approve the app in System Settings.** The GitHub release body discloses this.
This is the same limited signing path used by earlier releases; prefer the
notarized workflow for public distribution when Developer ID credentials are
available.

Installs read `releases/latest/download/appcast.xml` (`SUFeedURL` in
`Glimmer/Info.plist`), so an installed copy sees the update at its next daily
check and asks before it installs. Nothing is pushed to a branch, and GitHub
Pages is not used.

For local release validation, `make dist` builds the signed, notarized app and
DMG without publishing. `scripts/check-release-app.sh` and
`scripts/check-release-dmg.sh` verify the signatures, tickets, and Gatekeeper
results on those actual artifacts. `make dist-dev` builds and checks the
Apple-Development-signed, non-notarized alternative and reports Gatekeeper's
actual result without treating its expected rejection as success.

The Homebrew cask is disabled because the currently published app artifacts fail
Gatekeeper. After a replacement release passes the artifact checks,
`make brew-bump` updates the cask locally; remove its `disable!` stanza in the
same reviewed change.

Release notes come from `CHANGELOG.md`, so write that section before publishing.
Each release is a `## <version> - <date>` heading followed by a flat list of
bullets, one per change a player will notice, written for them.
`scripts/changelog.py` lifts that block into the GitHub release body and, as
HTML, into the appcast `<description>` Sparkle shows as “what's new”
(`update-appcast.py --backfill` adds it to older items). The DMG is styled by
`scripts/make-dmg.sh` (background, window bounds, icon positions, baked-in
`.DS_Store`); re-run `make dmg-background` after changing that layout.

## 3. Signing credentials

Fresh machine, one-time: `make creds-init`, fill in the file it prints (or set
its `OP_SOURCE`), then `make codesign-setup setup-notary sparkle-keys`. Secrets
live in that 0600 file and its 1Password item, never in the repo.

### GitHub release environment

Configure the repository's `release` environment with these Actions secrets. The
workflow writes temporary key files and its credentials file under the runner's
private temporary directory, then removes them when the runner exits. Do not
copy these values into repository variables or files.

| Secret                      | Value                                               |
| --------------------------- | --------------------------------------------------- |
| `DEVELOPER_ID_NAME`         | Exact `Developer ID Application: ...` identity name |
| `DEVELOPER_ID_P12_BASE64`   | Base64-encoded Developer ID `.p12` export           |
| `DEVELOPER_ID_P12_PASSWORD` | `.p12` export password                              |
| `NOTARY_KEY_BASE64`         | Base64-encoded App Store Connect `.p8` key          |
| `NOTARY_KEY_ID`             | App Store Connect key ID                            |
| `NOTARY_ISSUER_ID`          | App Store Connect issuer ID                         |
| `SPARKLE_ED_PRIVATE_KEY`    | Sparkle EdDSA private key text                      |

Restrict the environment's deployment tags to version tags. Enable publication
only after a release candidate has passed the local artifact checks above.

These belong to your Developer ID, not to Glimmer: `~/.config/developer-id/` and
`~/Library/Keychains/developer-id.keychain-db` hold one identity and one
`notary` profile, and any other project can sign and notarize with them. Exactly
one Developer ID Application identity should be reachable, or signing by name
fails as ambiguous.

- The **Developer ID Application certificate** (`P12_PATH`, `P12_PASSWORD`)
  signs the app. Create it on the G2 Sub-CA; the previous sub-CA ends
  2027-02-01, and nothing it issued signs after that. Apple says G2 certificates
  expire yearly, though the first one issued here runs to 2031-09-17, so go by
  the date `make dist` prints. Shipped builds keep working after their
  certificate expires, because every signature is timestamped. Never revoke a
  certificate that signed a release: Gatekeeper would then block those builds.
- The **App Store Connect team API key** (`NOTARY_KEY_PATH`, `NOTARY_KEY_ID`,
  `NOTARY_ISSUER_ID`) notarizes through the `notary` notarytool profile that
  `make setup-notary` stores in the signing keychain. Developer access is
  enough. It doesn't expire and doesn't depend on the Apple ID password.

`make dist` prints the certificate's expiry and warns 60 days ahead. To renew:

```bash
D=~/.config/developer-id; umask 077
/usr/bin/openssl req -new -newkey rsa:2048 -nodes -keyout $D/developer-id.key \
    -out ~/Downloads/Glimmer-Developer-ID.certSigningRequest -subj "/CN=Glimmer Developer ID/C=US"
# developer.apple.com → Certificates → + → Developer ID Application → G2 Sub-CA → upload it
/usr/bin/openssl x509 -inform der -in ~/Downloads/developerID_application.cer -out $D/developer-id.pem
P="$(/usr/bin/openssl rand -base64 24)"
/usr/bin/openssl pkcs12 -export -inkey $D/developer-id.key -in $D/developer-id.pem \
    -out $D/developer-id.p12 -passout "pass:$P"
scripts/signing-creds.sh set P12_PATH $D/developer-id.p12
scripts/signing-creds.sh set P12_PASSWORD "$P"
rm $D/developer-id.key $D/developer-id.pem
make codesign-teardown codesign-setup setup-notary
```

Then put the new `.p12` and its passphrase in the 1Password item. The signing
identity is matched by name and the app's designated requirement by team, so
updates, privacy permissions and the helpers carry over to the new certificate.
