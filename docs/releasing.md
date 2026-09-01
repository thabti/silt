# Releasing a signed build

How to go from source to a `.dmg` you can hand to anyone — signed, notarized, and stapled, so
Gatekeeper opens it without warnings. The whole pipeline is `make release`; this guide explains
what each stage does, the one-time setup, and how to tell whether it worked.

## The pipeline at a glance

```
make signed      Developer ID build — hardened runtime, secure timestamp, verified
   │
make dmg         compress the .app into dist/Silt-<version>.dmg, sign the dmg too
   │
make notarize    upload to Apple's notary service, wait for the verdict
   │
make staple      attach the notarization ticket to the dmg, validate it
   │
make release     = all of the above, in order
```

Each stage runs the ones before it, so `make release` from a clean checkout is the only
command a release actually needs.

## Prerequisites

1. **A Developer ID Application certificate** in your login keychain. Check:

   ```bash
   security find-identity -p codesigning -v | grep "Developer ID Application"
   ```

   You should see `Developer ID Application: Sabeur Thabti (N762FB52VL)`. If it is missing,
   create one at [developer.apple.com › Certificates](https://developer.apple.com/account/resources/certificates/list)
   (type: *Developer ID Application*) and double-click the downloaded `.cer` to install it.
   The private key must be present too — a cert without its key cannot sign, and shows a
   missing-key badge in Keychain Access.

2. **Notary credentials stored once** under the profile name the Makefile expects
   (`silt-notary`):

   ```bash
   xcrun notarytool store-credentials silt-notary \
     --apple-id <your-apple-id-email> --team-id N762FB52VL
   ```

   It prompts for an **app-specific password** — generate one at
   [account.apple.com › Sign-In and Security › App-Specific Passwords](https://account.apple.com/account/manage)
   (your normal Apple ID password will not work). The credentials land in the keychain;
   this never needs repeating unless you revoke the password.

Defaults live at the top of the `Makefile` and can be overridden per invocation:

```bash
make release TEAM_ID=XXXXXXXXXX NOTARY_PROFILE=other-profile
```

## What each stage actually does

### `make signed`

An ordinary Release build with the signing settings overridden on the command line — the
committed `project.yml` stays unsigned (`CODE_SIGN_IDENTITY: "-"`) so day-to-day `make build`
needs no team or keychain:

| Setting | Why |
|---|---|
| `DEVELOPMENT_TEAM=N762FB52VL` | selects the identity |
| `CODE_SIGN_IDENTITY="Developer ID Application"` | the only cert type Gatekeeper accepts outside the App Store |
| `ENABLE_HARDENED_RUNTIME=YES` | notarization refuses binaries without it |
| `--timestamp` | secure timestamp, so the signature outlives the certificate |
| `--options=runtime` | stamps the hardened-runtime flag into the signature |

It finishes by running `make verify`, which must print `valid on disk`,
`TeamIdentifier=N762FB52VL`, and `flags=0x10000(runtime)`.

### `make dmg`

`hdiutil create` compresses the app into `dist/Silt-<version>.dmg` (version read from
`MARKETING_VERSION` in `project.yml`), then the dmg itself is signed. Signing the container
as well as the app is what lets Gatekeeper evaluate the download as a whole.

### `make notarize`

`notarytool submit --wait` uploads the dmg and blocks until Apple's automated scan returns.
Typical wait is one to five minutes. Two outcomes:

- **`status: Accepted`** — proceed; `make staple` runs automatically.
- **`status: Invalid`** — get the reasons:

  ```bash
  xcrun notarytool log <submission-id> --keychain-profile silt-notary
  ```

  The log names each offending file and rule. The usual culprits for this project would be a
  build signed without hardened runtime or without a timestamp — both impossible via
  `make signed`, so in practice an Invalid here means a stale app in `build/` (run
  `make clean` and retry).

### `make staple`

Attaches the notarization ticket to the dmg so Gatekeeper can verify it **offline** — without
stapling, the first launch needs a network round-trip to Apple. `stapler validate` confirms.

## Verifying the result

```bash
# the app: signature, team, hardened runtime
codesign --verify --deep --strict --verbose=2 build/Build/Products/Release/Silt.app
codesign -dv build/Build/Products/Release/Silt.app 2>&1 | grep -E 'Authority|TeamIdentifier|flags'

# the dmg: what Gatekeeper will say
spctl --assess -vv --type open --context context:primary-signature dist/Silt-*.dmg
```

`spctl` verdicts, in pipeline order:

| Verdict | Meaning |
|---|---|
| `rejected · Unnotarized Developer ID` | signed correctly, not yet notarized — expected after `make dmg` |
| `accepted · source=Notarized Developer ID` | the finished state after `make release` |
| `rejected` with no Developer ID origin | signing itself failed — check `security find-identity` |

## Troubleshooting

- **"No signing certificate found" / errSecInternalComponent** — the keychain is locked or
  the identity is missing its private key. `security unlock-keychain login.keychain-db`, and
  check the cert in Keychain Access.
- **Prompt: "codesign wants to sign using key…"** — click *Always Allow*, or the timestamp
  server round-trip can time the prompt out mid-build.
- **`store-credentials` rejects the password** — you used the Apple ID password; it needs an
  app-specific one.
- **Notarization hangs** — `--wait` polls; check status independently with
  `xcrun notarytool history --keychain-profile silt-notary`.
- **Stapler error 65** — the submission was not `Accepted`, or you stapled the app instead of
  the dmg the ticket was issued for.

## What is deliberately not automated

- **Credentials never live in the repo.** The Makefile references a keychain profile by name;
  there is no password, key, or `.p8` anywhere in git. Keep it that way — including not
  committing the Developer ID `.cer`/private key pair (they belong in the keychain only).
- **No auto-upload.** The pipeline ends with a stapled dmg in `dist/` (git-ignored).
  Publishing it — GitHub release, website, wherever — is a human decision.
