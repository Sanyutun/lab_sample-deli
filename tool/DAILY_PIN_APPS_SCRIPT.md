# Daily PIN mail through Google Sheets + Apps Script

> **Not used by the current office app.** Sensitive actions now ask for the
> Admin PIN, so no daily code is generated, emailed or published. This guide is
> kept only in case the daily-PIN feature is ever switched back on.

The app no longer talks to Gmail over SMTP, so no sender address or app password
is stored. It writes today's PINs and each user's Gmail to the `DailyPins` tab.
An Apps Script in the same spreadsheet does the sending.

## One-time setup

1. In **Admin Settings → Google Sheets credentials**, make sure the spreadsheet
   ID and service-account JSON are saved. The app must be able to write the
   `DailyPins` tab.
2. In **Admin Settings → Users**, set each active user's Gmail address.
3. Open the same spreadsheet → **Extensions → Apps Script**.
4. Paste the contents of `tool/daily_pin_gsheet.gs` into the script editor and
   save.
5. Run `setup()` once and allow the Gmail permission. This creates a trigger
   that runs `sendDailyPins` every minute.
6. Press **RESEND TODAY'S PINS** in Admin Settings. A new row per user is
   appended to `DailyPins`, and the script mails it within a minute.

## How it sends

- New rows have an empty `Sent` cell. The script mails each such row once, then
  writes the time to `Sent`.
- **RESEND** appends fresh rows with an empty `Sent` cell, so the script sends
  them again.
- The sender is the Google account that authorized the script. Apps Script sends
  through Gmail internally, so no app password is stored in the app.
- Google Workspace domains can restrict `MailApp`; if the trigger logs an
  authorization error, ask the Workspace admin to allow Apps Script to send mail.
- If a mail fails, the `Sent` cell shows `ERROR: ...`. Fix the address and clear
  that cell (or RESEND) to try again.
- A `DailyPins` tab created by an older app version is upgraded automatically:
  old rows are moved to the new columns and marked `migrated` so yesterday's
  PINs are not emailed again.
