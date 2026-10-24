/**
 * Daily PIN mailer for the DailyPins tab.
 *
 * Setup (once):
 *  1. Open the spreadsheet that is set in Admin Settings.
 *  2. Extensions > Apps Script. Paste this file, replacing the default code.
 *  3. Run setup() once and allow the Gmail permission.
 *
 * The app writes one row per user each day:
 *   Date | Time | User ID | Name | Role | Email | PIN | Sent
 *
 * This script is triggered every minute. It mails every row whose Sent cell is
 * empty, then stamps that cell. The sender is the Gmail account that authorized
 * the script, so no app password is needed in the Flutter app.
 */
const SHEET_NAME = 'DailyPins';
const SENT_COLUMN = 8; // H

function setup() {
  ScriptApp.getProjectTriggers()
    .filter((t) => t.getHandlerFunction() === 'sendDailyPins')
    .forEach((t) => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('sendDailyPins').timeBased().everyMinutes(1).create();
}

function sendDailyPins() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  if (!sheet || sheet.getLastRow() < 2) return;

  const rows = sheet
    .getRange(2, 1, sheet.getLastRow() - 1, SENT_COLUMN)
    .getValues();

  rows.forEach((row, index) => {
    const email = String(row[5]).trim();
    const pin = String(row[6]).trim();
    const alreadySent = String(row[7]).trim() !== '';
    if (!email || !pin || alreadySent) return;

    const name = String(row[3] || 'there');
    const date = String(row[0] || '');
    const sentCell = sheet.getRange(index + 2, SENT_COLUMN);
    try {
      MailApp.sendEmail({
        to: email,
        subject: 'Your daily PIN for ' + date,
        body:
          'Hello ' + name + ',\n\n' +
          'Your PIN for ' + date + ' is: ' + pin + '\n\n' +
          'Enter it when asked to delete a transaction, take a payment back, ' +
          'or correct a transaction. A new PIN is created each day; ' +
          "yesterday's PIN stops working.\n\n" +
          'TWOK Sample Deli',
      });
      sentCell.setValue(new Date());
    } catch (e) {
      sentCell.setValue('ERROR: ' + e.message);
    }
  });
}
