# publish-extension-action

GitHub Action: publish an ENCY extension to the [ENCY Extension Store](https://apps.encycam.com).

Push a version tag in your extension repo — the workflow builds, packs and publishes. No files
are copied or uploaded by hand. See
[ency-extension-template](https://github.com/EncySoftware/ency-extension-template) for a
ready-to-fork repo wired to this action.

## What it does

1. **Pack**: by default the flat build-output folder is uploaded to the store backend, which
   builds the `.nupkg` itself (server-side packing — no tooling on the runner; the `version`
   from the git tag is stamped into the nuspec and the packed `package.info.json`).
   Alternatives: pass a ready `nupkg`, or pass `pack-cli` to pack on the runner with the ENCY CLI.
2. **Publish**: the staged package goes through `POST /extensions` (backend pushes to the feed).
   The token's subject becomes the extension **owner**; new extensions wait for moderation.

## Usage

```yaml
- name: Publish to the ENCY store
  id: publish
  uses: EncySoftware/publish-extension-action@v1
  with:
    token: ${{ secrets.ENCY_STORE_TOKEN }}
    folder: src/bin/Release          # flat build output (dotnet build, NOT publish); the backend packs it
    version: ${{ env.PKG_VERSION }}  # e.g. 1.2.3 from tag v1.2.3

- run: echo "Published ${{ steps.publish.outputs.card-url }}"
```

Or with a package you packed yourself:

```yaml
- uses: EncySoftware/publish-extension-action@v1
  with:
    token: ${{ secrets.ENCY_STORE_TOKEN }}
    nupkg: out/*.nupkg
```

## Inputs

| Input | Required | Default | Notes |
|---|---|---|---|
| `token` | yes | — | Store bearer token (Keycloak realm `licsys`). Keep it in a repo secret. |
| `nupkg` | no* | — | Path/glob of a ready `.nupkg` (newest match wins). |
| `folder` | no* | — | Flat build-output folder: `<Name>.dll` + `<Name>.settings.json` + `package.info.json`. The backend packs it (server-side). Use `dotnet build` — `dotnet publish` drags SDK dlls into the output. |
| `pack-cli` | no | — | Optional: pack on the runner with the ENCY CLI instead of server-side packing. |
| `version` | no | keep file value | Version stamped into the package (folder mode; typically from the git tag). |
| `licensed` | no | `false` | Publish as a paid extension. |
| `dry-run` | no | `false` | Pack + server-side validation (parse-nupkg), skip the publish step. |
| `api-base` | no | `https://apps.encycam.com/api` | Override for test environments. |

\* exactly one of `nupkg` / `folder`.

## Outputs

| Output | Example |
|---|---|
| `package-id` | `MyExtension` |
| `version` | `1.2.3` |
| `slug` | `myextension` |
| `card-url` | `https://apps.encycam.com/extension/myextension` |

## Package requirements

The store validates on the server (`parse-nupkg` → 400 otherwise):

- `*.settings.json` + the extension `.dll` inside the package (flat layout, as the pack CLI emits);
- `package.info.json` with `tags` containing the **`ency-extension` marker** — without it the
  catalog will not index the package;
- `sdkVersion` in `package.info.json` drives the "minimal ENCY version" shown on the card.

## Consents the store checks

Two, and neither is an input of this action — they belong to the publisher and to the package:

- **Developer registration and the Developer Agreement**, once per publisher, done in a browser at
  `<store>/publish`: a short registration, then I Agree. Until then, a run is refused with 403
  and that link; the store's sentence
  is printed as the run's error, and the summary turns it into a button.
- **The Schedule A declaration**, with every submission, read from `reservedDomains` in
  `package.info.json` (Schedule B §B.3.2): `[]` is the answer "none" — the extension provides
  nothing Schedule A lists — and otherwise each area it does provide is a
  `{"domain", "entitlement", "capabilities"}` entry (`capabilities` optional), the entitlement being
  the licence Schedule A assigns to that area. The first run with an answer stops with a link to
  confirm it in the store; the summary turns it into a button. After that the store asks again only
  when the answer changes, when a new version of Schedule A comes into force, when the words of the
  statements change, or when a run is credited to someone else: once the repository is bound to the
  package (its first publication binds it), every run from it is credited to whoever bound it, so a
  colleague's run uses that person's confirmation. Without the key,
  the store publishes anyway **until 1 November 2026** and says so in an `X-Store-Warning` header,
  which this action prints as a run annotation and a line in the job summary. From that date it is
  a refusal instead. Areas and their licences:
  <https://encycam.com/legal/extension-store/reserved-functionality/>.

## Auth: token vs OIDC trusted publishing

- **First publish of a new extension** — a store token (any valid Keycloak `licsys` access
  token) in the `token` input. This publish also auto-registers the repository as the
  package's **trusted publisher**.
- **Every publish after that** — leave `token` empty and add `permissions: id-token: write`
  to the workflow: the action authenticates with the run's own GitHub OIDC token. No secrets,
  nothing expires, and the repository can publish only its own package. Owners manage the
  binding via `GET/PUT/DELETE /api/extensions/{slug}/trusted-publisher`.

## Moderation

A **new** extension (first publish of its packageId) lands hidden from the catalog until a
store moderator approves it; the card link from the action output already works, so you can
review and share it right away. New versions of an approved extension go live immediately.
The action reports the GitHub repo + commit sha with each publish (provenance), and the
backend records them on the version for the audit trail.
