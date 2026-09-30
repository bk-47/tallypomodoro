// tally → google sheets
// Paste this into Extensions → Apps Script on the sheet you want to log to,
// then Deploy → New deployment → Web app, Execute as: Me, Who has access: Anyone.
// Copy the web app URL into tally's settings.

const SHEET_NAME = 'Log';
const HEADERS = ['Date', 'Start', 'End', 'Label', 'Type', 'Minutes', 'Completed', 'Added min', 'ID'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const body = JSON.parse(e.postData.contents);
    if (body.test) return reply({ ok: true, test: true });

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(SHEET_NAME);
    if (!sheet) sheet = ss.insertSheet(SHEET_NAME);
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(HEADERS);
      sheet.setFrozenRows(1);
      sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
    }

    // Rows already in the sheet (matched by ID) are updated if they changed, e.g. a renamed label.
    // New rows are added at the bottom. Resending never duplicates.
    const last = sheet.getLastRow();
    const existing = last > 1 ? sheet.getRange(2, 1, last - 1, HEADERS.length).getValues() : [];
    const index = new Map(existing.map((r, i) => [String(r[HEADERS.length - 1]), i]));

    const fresh = [];
    let updated = 0;
    (body.rows || []).forEach(r => {
      const row = [r.date, r.start, r.end, r.label, r.type, r.minutes, r.completed ? 'Yes' : 'No', r.added, r.id];
      if (index.has(r.id)) {
        const i = index.get(r.id);
        if (i >= 0 && String(existing[i][3]) !== String(r.label)) {
          sheet.getRange(i + 2, 4).setValue(r.label);
          updated++;
        }
      } else {
        fresh.push(row);
        index.set(r.id, -1);
      }
    });

    if (fresh.length) {
      sheet.getRange(last + 1, 1, fresh.length, HEADERS.length).setValues(fresh);
    }
    return reply({ ok: true, added: fresh.length, updated: updated });
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
