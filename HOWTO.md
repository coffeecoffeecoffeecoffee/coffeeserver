# HOWTO

Common admin/operator tasks for CoffeeServer. All routes are under `/api/v2/`. Examples use `curl`; you can also drive these through `CoffeeServer.paw`.

## 1. Create a new user

`POST /api/v2/users` — no auth required.

```bash
curl -X POST "https://YOUR_HOST/api/v2/users" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Ada Lovelace",
    "email": "ada@example.com",
    "password": "correct-horse-battery-staple",
    "confirmPassword": "correct-horse-battery-staple"
  }'
```

- `email` must be unique (case-insensitive) and `password`/`confirmPassword` must match, or the request fails with `400 Bad Request`.
- On success you get back the new user's public profile (`201 Created`).
- To log in afterward: `POST /api/v2/users/login` with HTTP Basic auth (email/password), which returns a session JWT to use as a Bearer token on protected routes.

## 2. Grant admin privileges to a user

Admin isn't a flag on the user — it's membership in the `admin` tag (see `Sources/App/Request+AdminCheck.swift`). Only an existing admin can attach the `admin` tag to someone else, so this always starts from an already-authenticated admin account.

1. **Log in as an existing admin** to get a Bearer token (`POST /api/v2/users/login`).
   - On a fresh install, the first admin is created automatically by the `AddSuperUser` migration using the `SERVER_ADMIN_EMAIL` / `SERVER_ADMIN_PASSWORD` values from your `.env` (see `env_example` and the README's Dev Sandbox setup). Log in with those credentials to bootstrap everything else.
2. **Find the `admin` tag's ID:**
   ```bash
   curl "https://YOUR_HOST/api/v2/tags" \
     -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
   ```
   Look for the tag named `admin` and note its `id`.
3. **Find the target user's ID** (`GET /api/v2/users` lists all users, admin-only).
4. **Attach the tag to the user:**
   ```bash
   curl -X POST "https://YOUR_HOST/api/v2/tags/ADMIN_TAG_ID/attach/USER_ID" \
     -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
   ```
   Returns `201 Created` on success. The user now passes `req.isAdmin()` checks and can create venues, groups, events, and manage other users.

Note: the `admin` tag itself cannot be deleted (`DELETE /api/v2/tags/:tagID` explicitly blocks it), so there's no accidental way to remove the admin role entirely from the system.

## 3. As an admin, create an event (including venues)

Creating an event requires an existing **interest group** and **venue**, plus an admin Bearer token.

### Step A: Find or create a venue

Check existing venues first:

```bash
curl "https://YOUR_HOST/api/v2/venues"
```

(`GET` is open to everyone; no auth needed to browse.) If the venue you need already exists, grab its `id` and skip to Step C.

Otherwise, create one (admin-only):

```bash
curl -X POST "https://YOUR_HOST/api/v2/venues" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Blue Bottle Coffee",
    "location": {
      "address": "300 Webster St, Oakland, CA",
      "title": "Blue Bottle - Old Oakland"
    }
  }'
```

Save the returned venue `id`.

### Step B: Find or create an interest group

Check existing groups:

```bash
curl "https://YOUR_HOST/api/v2/groups"
```

If you need a new one (admin-only):

```bash
curl -X POST "https://YOUR_HOST/api/v2/groups" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "SF iOS Coffee",
    "short": "sf-ios-coffee"
  }'
```

Save the returned group `id`.

### Step C: Create the event

```bash
curl -X POST "https://YOUR_HOST/api/v2/events" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Saturday Coffee Meetup",
    "groupID": "GROUP_ID_FROM_STEP_B",
    "venue": { "id": "VENUE_ID_FROM_STEP_A" },
    "startAt": "2026-06-01T10:00:00-07:00",
    "endAt": "2026-06-01T11:30:00-07:00"
  }'
```

Non-admin requests get `401 Unauthorized`. A missing/unknown `groupID` returns an error — double-check the ID from Step B if that happens.

**Note:** you don't strictly have to create the venue in a separate call. `POST /api/v2/events` will reuse an existing venue if you pass its `id`, but if you omit `id` and instead pass a full `venue.location` object, the server will look for a matching venue by address (falling back to Apple Place ID / coordinates) and create a new one automatically if none matches (see `EventData.saveAsEvent` in `Sources/App/Models/EventData.swift`). Creating the venue explicitly first (Step A) is recommended when you want to confirm the venue's details or reuse it across multiple events.
