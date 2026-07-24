# publish-extension-action

GitHub Action: publish an ENCY extension to the [ENCY Extension Store](https://dmc.encycam.com/store).

Push a version tag in your extension repo — the workflow builds, packs and publishes. No files
are copied or uploaded by hand. See
[ency-extension-template](https://github.com/ENCY-SOFTWARE-LTD/ency-extension-template) for a
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
  uses: ENCY-SOFTWARE-LTD/publish-extension-action@v1
  with:
    token: ${{ secrets.ENCY_STORE_TOKEN }}
    folder: src/bin/Release          # flat build output (dotnet build, NOT publish); the backend packs it
    version: ${{ env.PKG_VERSION }}  # e.g. 1.2.3 from tag v1.2.3

- run: echo "Published ${{ steps.publish.outputs.card-url }}"
```

Or with a package you packed yourself:

```yaml
- uses: ENCY-SOFTWARE-LTD/publish-extension-action@v1
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
| `api-base` | no | `https://dmc.encycam.com/store/api` | Override for test environments. |

\* exactly one of `nupkg` / `folder`.

## Outputs

| Output | Example |
|---|---|
| `package-id` | `MyExtension` |
| `version` | `1.2.3` |
| `slug` | `myextension` |
| `card-url` | `https://dmc.encycam.com/store/extension/myextension` |

## Package requirements

The store validates on the server (`parse-nupkg` → 400 otherwise):

- `*.settings.json` + the extension `.dll` inside the package (flat layout, as the pack CLI emits);
- `package.info.json` with `tags` containing the **`ency-extension` marker** — without it the
  catalog will not index the package;
- `sdkVersion` in `package.info.json` drives the "minimal ENCY version" shown on the card.

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
