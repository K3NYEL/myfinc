# MyFinc notification center

The public manifest consumed by the app is `/updates/manifest.json`. Keep it valid JSON and do not add notices for events that have not actually happened.

## Publish a notification

Add an object to `notifications`:

```json
{
  "id": "maintenance-2026-10",
  "title": "Scheduled maintenance",
  "message": "The service may be temporarily unavailable during maintenance.",
  "publishedAt": "2026-10-11T16:00:00Z",
  "level": "info"
}
```

Use a unique `id`. Allowed levels are `info`, `success`, `warning`, and `error`. Remove or replace old notices when they are no longer relevant. Keep at most 50 notifications.

## Publish a patch notice

Add an object to `patches` only when a real patch/release exists:

```json
{
  "id": "patch-0.1.1",
  "version": "0.1.1",
  "title": "Maintenance update",
  "summary": "Brief summary of the changes.",
  "notes": [
    "Describe a real fix or improvement."
  ],
  "releaseUrl": "https://github.com/K3NYEL/myfinc/releases/tag/v0.1.1",
  "publishedAt": "2026-10-11T16:00:00Z",
  "required": false
}
```

The release URL must point to a MyFinc GitHub Release. Patches in this manifest are trusted release notes and links only; they must never contain executable code, shell commands, or instructions for the app to download and run arbitrary code. `required` is informational metadata; do not mark a patch as required unless the app's update flow has been designed and verified to enforce it.

## Manifest rules

- `schemaVersion` must be `1`.
- Update `updatedAt` whenever the manifest changes, using ISO-8601 UTC time.
- `notifications` must contain no more than 50 entries.
- `patches` must contain no more than 30 entries.
- IDs must be unique across both lists.
- Notification titles/messages and patch titles/summaries must be non-empty.
- The validation workflow checks the manifest on relevant pushes and pull requests.

After merging a change into `main`, GitHub Pages publishes the manifest. Verify the public URL before telling users that a notice or patch is available.
