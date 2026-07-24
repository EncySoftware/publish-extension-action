# publish-extension-action

GitHub Action: publish an ENCY extension to the [ENCY Extension Store](https://dmc.encycam.com/store).

Push a version tag in your extension repo — the workflow builds, packs and publishes. No files
are copied or uploaded by hand. See
[ency-extension-template](https://github.com/ENCY-SOFTWARE-LTD/ency-extension-template) for a
ready-to-fork repo wired to this action.

## What it does

1. **Pack** (optional): stamps `version` into `package.info.json` and packs a flat build-output
   folder into an ENCY `.nupkg` with the ENCY pack CLI. Skip this by passing a ready `nupkg`.
2. **Publish**: `POST /extensions/parse-nupkg` (stages the original bytes — the backend never
   repacks free packages) → `POST /extensions` (backend pushes to the feed). The token's subject
   becomes the extension **owner**.

## Usage

```yaml
- name: Publish to the ENCY store
  id: publish
  uses: ENCY-SOFTWARE-LTD/publish-extension-action@v1
  with:
    token: ${{ secrets.ENCY_STORE_TOKEN }}
    folder: src/bin/Release          # flat build output (dotnet build, NOT publish)
    pack-cli: ${{ env.PACK_CLI }}    # path to the ENCY pack CLI
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
| `folder` | no* | — | Flat build-output folder to pack: `<Name>.dll` + `<Name>.settings.json` + `package.info.json`. Use `dotnet build` — `dotnet publish` drags SDK dlls into the output. |
| `pack-cli` | with `folder` | — | Path to the ENCY pack CLI executable. |
| `version` | no | keep file value | Stamped into `package.info.json` before packing (folder mode only). |
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

## Getting a token

Any valid Keycloak `licsys` access token works today (no role check yet). For CI use a
long-lived offline/service token stored as a repo secret — ask the store team. Browser tokens
from the store site work for manual tries but expire within hours.

## Moderation

Extensions with the `unlisted` flag stay out of the public catalog but remain reachable by
direct link — publishing a new version does not reset the flag. The planned CI-publish gate
(new extensions land unlisted until approved) builds on this.
