# Delivery Companion app — migration & sync plan

The office app (`lab_commission`) stays the single source of truth and keeps
running exactly as before. The delivery-man companion app
(`companion/`, `lab_delivery_companion`) is a **read-only client** that talks to
the office app over the office phone's own Wi-Fi/LAN. There is no cloud service
and no second database.

## 1. How the two apps connect

```
Delivery man phone                 Office phone (same Wi-Fi)
┌─────────────────────┐            ┌──────────────────────────────┐
│ lab_delivery_       │  HTTP/JSON │ Lab Commission               │
│ companion           │ ─────────▶ │  HttpServer on :8787         │
│ (read-only client)  │  Bearer    │  → CompanionService          │
│                     │  token     │  → existing repositories     │
└─────────────────────┘            │  → existing SQLite database  │
                                   └──────────────────────────────┘
```

The office app runs a small HTTP server (`lib/companion/companion_api_server.dart`)
inside the existing app; it reuses the existing repositories, so companion
figures are the same numbers staff see. The shared wire contract lives in
`packages/lab_commission_contract` so the two apps cannot drift.

## 2. Office-side setup (once)

1. Update the office app to the build that includes schema **v7**. The upgrade
   is additive: three tables are created and two columns are added, no existing
   table or row is changed, so current data is untouched.
2. Open **Companion Accounts** in the office app and register each delivery man:
   pick the delivery man, choose a login ID and a PIN (≥ 4 digits). PINs are
   stored salted and hashed — never in plain text.
3. Open the **Companion Server** screen and tap **Start**. It shows the device's
   LAN address, e.g. `192.168.1.20:8787`. All phones must be on the same network.
   The same screen holds the **GPS tracking policy**: how often a phone captures
   a fix, and how long it keeps a sent fix. Phones pick the saved values up on
   their next sign-in; the office's own 20-minute route window is not changed.
4. Staff can deactivate an account, reset a PIN (which ends all that man's
   sessions) or stop the server at any time.
5. Open **Delivery Map** (admin) to see where each delivery man was last seen:
   one pin per man, coloured teal under 15 minutes old, orange under an hour,
   red beyond that. Tap a pin for the capture time, accuracy and receipt, if
   any. It refreshes every 30 seconds, or tap the refresh icon. Map tiles come
   from OpenStreetMap, so the office phone needs internet.

## 3. Companion-side setup (per phone)

1. Install `lab_delivery_companion`.
2. On first run, enter the server address shown on the office screen
   (`192.168.1.20:8787`). It is remembered; it can be changed later in
   **Profile → Settings & logout**.
3. Sign in with the delivery ID/login and PIN from the office. The app keeps
   only a bearer token in the phone's secure keystore.
4. The **Dashboard** opens **My delivery board**: the man's own positions, in
   groups of 10 with milestone markers and paid/unpaid marks, built by the office
   from the same records it shows staff. Only groups that hold a delivery are
   sent (numbering is unchanged), and it is read-only: there is no delivery-man
   picker, and it can only ever show his own deliveries.

## 4. Data model change (schema v7)

| New table | Purpose |
|-----------|---------|
| `delivery_man_accounts` | login ID, salted PIN hash, active flag, hashed QR token, last login |
| `delivery_sessions` | hashed bearer tokens with expiry and revoke time |
| `delivery_locations` | GPS fixes: lat, lng, accuracy (m), captured time, the office's own receipt time (`received_at`), optional barcode, and the phone's own id for the fix (`client_id`, so a retry is not stored twice) |
| `delivery_trip_points` | one delivered receipt's preserved route: the fixes from the 20 minutes before it was recorded, linked to the barcode, the commission and the delivery man |

Raw fixes are short-lived: the office deletes a fix once it received it more
than **20 minutes** ago. Anything a delivery needs is copied into
`delivery_trip_points` when staff record the delivery, and that copy is kept, so
a receipt's route still works weeks later. Retaining a route is not a claim that
a test was performed — it never changes a commission.

Backup export includes accounts, locations and trip points. Everything else is
unchanged.

## 5. Security model

- **Authorization is server-side.** Every request is authenticated from the
  bearer token; the delivery man id is taken from the session, never from the
  request body or URL. One man can never read another's records.
- **Read-only money.** The API has no route that creates or edits a commission,
  payment, reward or rule. A POST to a financial path answers `404`. The client
  interface exposes no such method either.
- **Secrets are hashed.** Only SHA-256 hashes of session and QR tokens are
  stored; a database leak does not hand out working tokens.
- **QR is opaque and revocable.** The code carries `lc1:<random token>` and no
  name, ID, phone or money. Issuing a new code invalidates the previous one;
  staff can revoke it. The office always re-verifies the code against the
  database before assigning a receipt.
- **Location is shared while signed in, and the user is told.** From sign-in to
  sign-out the app runs an Android foreground service (the ongoing notification)
  and records a fix on the interval the office sets (2 minutes by default).
  A fix is stored on the phone first
  and forwarded to the office whenever the server is reachable; each fix is
  marked sent only after the office acknowledges it. Signing out stops the
  service and discards any unsent fixes, so one man's fixes are never filed
  against the next man who signs in on the same phone. Accuracy is reported
  honestly, and if no fix is available the app says so rather than claiming a
  location.
- **What stays on the phone.** The phone keeps sent fixes for the office-set
  window (3 days by default), then deletes them. Unsent fixes are never
  deleted — an offline backlog lives until it reaches the office, however long
  that takes.
- **Battery.** The Location tab warns when Android is still optimising the app
  (which can stop background tracking) and offers a one-tap way to exempt it.
- **Routes are visible on the office side**, not to the delivery man: he cannot
  read anyone's route, and the API answers `404` for a receipt that is not his.

## 5b. Office-side route history

1. Scan a receipt as usual: **Scan → barcode → delivery man → amount → save**.
   Saving copies the man's last 20 minutes of fixes onto that commission.
2. On the **success screen**, tap **VIEW TRIP (LAST 20 MIN)**. The same route is
   reachable later from **History → Commission History → Trip** on any row.
3. The screen shows the route line with a numbered pin per fix and a list of
   each point's recorded time and accuracy. Tap a list row to centre the map on
   that point.
4. Missing data is stated, never drawn: a gap longer than 5 minutes (or an
   impossible jump) breaks the line, and a red marker plus a banner marks it.
   Poor or unreported accuracy is called out too. The pin turns orange for a
   point worse than 50 m.
5. If no fix was kept, the screen says so and shows no route.
6. **Offline till?** If the man's phone had no signal when staff saved, his
   fixes reach the office later and attach themselves to that receipt as they
   arrive — only points from the same 20-minute window, and only once. Re-syncing
   an already-stored fix never duplicates a point.

## 6. Offline behaviour

The app caches the last synced figures **per delivery man**. When the office is
unreachable it shows that cached copy behind an "offline / last synced" banner;
it never invents or edits a figure. An expired or revoked session signs the user
out instead of falling back to stale data. Logging out wipes the cached data and
the token from the phone.

## 7. Rollout checklist

- [ ] Ship office build with schema v7 and the Companion Server screen.
- [ ] Confirm the office phone's LAN address is reachable from a companion phone.
- [ ] Register accounts and hand out login IDs + PINs privately.
- [ ] Install the companion app, set the address, sign in.
- [ ] Run through: dashboard totals, commission list + filters + detail, rewards,
      my delivery board (positions, milestones, only his own deliveries), QR scan
      at the office, location sharing (notification + "Sent"/"Waiting" marks),
      then sign out.
- [ ] Record a delivery with the app open in the background and check the route
      on **VIEW TRIP (LAST 20 MIN)** — including the no-fix and gap wording.

## 8. Known limits (by design for a LAN-only setup)

- Plain HTTP on the local network: fine on a trusted office Wi-Fi, not intended
  to be exposed to the public internet. Add TLS or a VPN before doing that.
- The sync server only runs while the office app is open and started.
- One office terminal is the host; no replication between offices. A second
  office terminal can *use* the host's database (section 9), which is sharing,
  not replication.
- Location tracking uses an Android foreground service, which keeps the app
  alive while it is backgrounded but does not stop Android from killing the
  process under memory pressure. If that happens, tracking resumes when the app
  is next opened; fixes already captured are not lost.
- Battery optimisation is handled by asking, not by forcing: if the man ignores
  the prompt, Android may still stop background fixes when the phone is idle.
- Routes are as good as the phone's GPS. Between two points the screen draws a
  straight line over a real road, so treat it as "where the phone was", and read
  the gaps and the accuracy, not just the line.
- Office map tiles come from OpenStreetMap's public servers, which need internet
  on the office phone and are not licensed for heavy or commercial use. Point
  the `TileLayer` at your own tile source before scaling up.
- On Android 13+ the app asks for notification permission when tracking starts;
  if the user refuses, the ongoing notification stays hidden from the drawer
  while the in-app "Location sharing is on" panel still shows the state.

## 9. Windows host and a second office terminal

The office app also builds for **Windows 11**. The Windows build is the
preferred home for the office data: it keeps the database (SQLite via
`sqflite_common_ffi`), runs the LAN server, and watches the Windows print
spooler so a printed receipt's invoice number (`001KHL` + digits) arrives in the
Print Monitor instead of being scanned. See section 5b's route-history steps for
the delivery flow, which is unchanged.

More than one office terminal can work on the **same** data. The host terminal
shows an **office link key** on the Companion Server screen; another terminal
enters that key plus the host's address under **Server** on its login screen.

- The client terminal runs the *same* code and services; only its storage
  changes — every read and write is one HTTP call to the host
  (`lib/data/storage/http_storage.dart` → the key-guarded gateway in
  `lib/companion/store_gateway.dart`).
- The gateway reaches **only the tables the app defines**, binds all values, and
  validates `orderBy`. Everything else about the database is out of reach.
- The **link key is a master credential**: whoever has it can read and change the
  office data (including staff PINs). Treat it like a password; regenerate it on
  the host if it leaks, then re-enter it on each client.
- Each terminal keeps its **own** staff session, keyed by a random terminal id
  stored beside the client's config, so signing in on one terminal does not sign
  in another.
- A client cannot run its own server (that would serve the host's data twice),
  and the Companion Server screen says so.
- If a client cannot reach the host, it starts on a plain "cannot open the office
  data" screen with **Retry** and **Server settings** — never on stale data.

Known limits of this mode: business rules are enforced by the *client*, not the
host, so two office terminals editing the same receipt in the same instant can
still double-record. Keep one terminal as the operator. The link is plain HTTP on
the LAN, like the companion surface — put it behind a VPN before crossing an
untrusted network.
