enum AppsScript {
    /// Same as AppsScript/Code.gs in the project folder.
    static let source = #"""
// tally → google sheets
// Paste this into Extensions → Apps Script on the sheet you want to log to,
// then Deploy → New deployment → Web app, Execute as: Me, Who has access: Anyone.
// Copy the web app URL into tally's settings.
//
// The second half of this file builds a dashboard tab. It builds itself when the first block
// arrives, or use "build dashboard" in tally's settings, or the "tally" menu in the sheet.

const SHEET_NAME = 'Log';
const SCRIPT_VERSION = 3;   // tally checks this to tell you when the script is out of date
const HEADERS = ['Date', 'Start', 'End', 'Label', 'Type', 'Minutes', 'Completed', 'Added min', 'ID'];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const body = JSON.parse(e.postData.contents);
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    if (body.test) return reply({ ok: true, test: true, version: SCRIPT_VERSION, sheet: ss.getUrl() });
    if (body.action === 'dashboard') {
      buildDashboard();
      return reply({ ok: true, dashboard: true, version: SCRIPT_VERSION });
    }

    const sheet = ensureLog_(ss);

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
      // Make room first: writing past the last row of a sheet fails.
      const need = last + fresh.length;
      if (need > sheet.getMaxRows()) sheet.insertRowsAfter(sheet.getMaxRows(), need - sheet.getMaxRows() + 500);
      sheet.getRange(last + 1, 1, fresh.length, HEADERS.length).setValues(fresh);
    }
    // First rows in a new sheet: build the dashboard without being asked. After that, list new labels.
    if (fresh.length) {
      try {
        if (!ss.getSheetByName(DASH)) buildDashboard();
        else fillCategories_(ss);
      } catch (err) { /* the rows are saved either way */ }
    }
    return reply({ ok: true, added: fresh.length, updated: updated, version: SCRIPT_VERSION });
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function ensureLog_(ss) {
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME);
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADERS);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
  }
  return sheet;
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}


// ===================================================================================
// dashboard
//
// Adds three tabs next to "Log":
//   dashboard   totals, by category, by day, by label, last 12 weeks, last 12 months
//   categories  optional: say which category each label belongs to
//   calc        hidden working tab, leave it alone
//
// Everything is live formulas, so the dashboard updates as tally adds rows.
// Rebuilding only redraws the dashboard; your categories are never overwritten.
// ===================================================================================

const DASH = 'dashboard';
const CALC = 'calc';
const CATS = 'categories';
const FONT = 'Courier Prime';
const INK = '#000000';
const MUTED = '#555555';
const VIEWS = ['this week', 'last week', 'this month', 'last month', 'last 30 days', 'all time', 'pick dates'];

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('tally')
    .addItem('rebuild dashboard', 'buildDashboard')
    .addItem('add new labels to categories', 'fillCategories')
    .addToUi();
}

function buildDashboard() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  ensureLog_(ss);
  // The dashboard tab has to exist before the calc formulas point at it.
  const dash = ss.getSheetByName(DASH) || ss.insertSheet(DASH);
  const hadControls = dash.getLastRow() >= 4;
  const keepView = hadControls ? dash.getRange('C3:C4').getValues() : null;
  const keepDates = hadControls ? dash.getRange('I3:I4').getValues() : null;

  if (!ss.getSheetByName(CATS)) buildCategories_(ss);
  buildCalc_(ss);
  buildDash_(ss, dash, keepView, keepDates);

  try {
    ss.setActiveSheet(dash);
    ss.moveActiveSheet(1);
  } catch (err) { /* not possible when tally asks for the build; the tab order doesn't matter */ }
}

// ---- categories -------------------------------------------------------------------

function buildCategories_(ss) {
  const sh = ss.insertSheet(CATS);
  sh.getRange(1, 1, sh.getMaxRows(), sh.getMaxColumns()).setFontFamily(FONT).setFontSize(10).setFontColor(INK);
  sh.getRange('A1:B1').setValues([['label', 'category']]).setFontWeight('bold')
    .setBorder(null, null, true, null, null, null, INK, SpreadsheetApp.BorderStyle.SOLID);
  sh.getRange('D1').setValue(
    'each label is its own category unless you change it here. type the same category next to ' +
    'several labels to group them (e.g. krny for krny showreel edit and krny ampla promo). ' +
    'new labels are added to this list as they come in.'
  ).setWrap(true).setFontColor(MUTED);
  sh.setColumnWidth(1, 260);
  sh.setColumnWidth(2, 160);
  sh.setColumnWidth(4, 340);
  sh.setFrozenRows(1);
  fillCategories_(ss);
}

function fillCategories() {
  fillCategories_(SpreadsheetApp.getActiveSpreadsheet());
}

/** Adds any work label not yet listed, with the full label as its category. */
function fillCategories_(ss) {
  const cats = ss.getSheetByName(CATS);
  const log = ss.getSheetByName(SHEET_NAME);
  if (!cats || !log || log.getLastRow() < 2) return;
  const listed = cats.getLastRow() > 1
    ? cats.getRange(2, 1, cats.getLastRow() - 1, 1).getValues().map(r => String(r[0]).trim().toLowerCase())
    : [];
  const have = new Set(listed);
  const add = [];
  log.getRange(2, 4, log.getLastRow() - 1, 2).getValues().forEach(([label, type]) => {
    const l = String(label).trim().toLowerCase();
    if (!l || String(type).toLowerCase() !== 'work' || have.has(l)) return;
    have.add(l);
    add.push([l, l]);
  });
  if (add.length) cats.getRange(cats.getLastRow() + 1, 1, add.length, 2).setValues(add);
}

// ---- calc (hidden) ----------------------------------------------------------------
// A:H   every row of Log, cleaned: date, label, category, type, hours, done (1/0), week, month
// J     category list for the dropdown
// M:T   work rows inside the chosen view and category
// V:AC  work rows in the chosen category, any date (for the 12 week / 12 month trends)
// AE2   first day of the view, AE3 last day
// AG:AI days worked (category), used for the longest streak
// AK:AM records (category, all time)

function buildCalc_(ss) {
  const sh = ss.getSheetByName(CALC) || ss.insertSheet(CALC);
  sh.clear();
  fit_(sh, 20000, 40);
  const head = ['date', 'label', 'category', 'type', 'hours', 'done', 'week', 'month'];

  sh.getRange('A1:H1').setValues([head]);
  sh.getRange('A2').setFormula(
    '=ARRAYFORMULA(IFERROR(LET(' +
    'raw, Log!A2:A, ' +
    'd, IFERROR(INT(IF(ISNUMBER(raw), raw, DATEVALUE(raw))), ), ' +
    'lab, LOWER(TRIM(Log!D2:D)), ' +
    'm, IFERROR(VLOOKUP(lab, {LOWER(TRIM(categories!A2:A)), LOWER(TRIM(categories!B2:B))}, 2, FALSE), ""), ' +
    'cat, IF(lab = "", "unlabelled", IF(m <> "", m, lab)), ' +
    'wk, IFERROR(d - WEEKDAY(d, 3), ), ' +
    'mo, IFERROR(DATE(YEAR(d), MONTH(d), 1), ), ' +
    'FILTER({d, IF(lab = "", "unlabelled", lab), cat, LOWER(TRIM(Log!E2:E)), IFERROR(Log!F2:F / 60, 0), ' +
    'IF(Log!G2:G = "Yes", 1, 0), wk, mo}, raw <> "")), ))'
  );

  sh.getRange('J1').setValue('categories');
  sh.getRange('J2').setValue('all');
  sh.getRange('J3').setFormula('=IFERROR(SORT(UNIQUE(FILTER(C2:C, D2:D = "work"))), )');

  sh.getRange('M1:T1').setValues([head]);
  sh.getRange('M2').setFormula(
    '=IFERROR(FILTER(A2:H, D2:D = "work", A2:A >= $AE$2, A2:A <= $AE$3, ' +
    '(' + DASH + '!$C$4 = "all") + (C2:C = ' + DASH + '!$C$4)), )'
  );

  sh.getRange('V1:AC1').setValues([head]);
  sh.getRange('V2').setFormula(
    '=IFERROR(FILTER(A2:H, D2:D = "work", (' + DASH + '!$C$4 = "all") + (C2:C = ' + DASH + '!$C$4)), )'
  );

  sh.getRange('AE1').setValue('from / to');
  sh.getRange('AE2').setFormula(
    '=LET(t, TODAY(), mon, t - WEEKDAY(t, 3), ' +
    'SWITCH(' + DASH + '!$C$3, ' +
    '"this week", mon, "last week", mon - 7, ' +
    '"this month", DATE(YEAR(t), MONTH(t), 1), "last month", DATE(YEAR(t), MONTH(t) - 1, 1), ' +
    '"last 30 days", t - 29, "all time", IF(MIN(A2:A) > 0, MIN(A2:A), t), ' +
    '"pick dates", ' + DASH + '!$I$3, mon))'
  );
  sh.getRange('AE3').setFormula(
    '=LET(t, TODAY(), mon, t - WEEKDAY(t, 3), ' +
    'SWITCH(' + DASH + '!$C$3, ' +
    '"this week", mon + 6, "last week", mon - 1, ' +
    '"this month", EOMONTH(t, 0), "last month", EOMONTH(t, -1), ' +
    '"last 30 days", t, "all time", t, ' +
    '"pick dates", ' + DASH + '!$I$4, mon + 6))'
  );

  // Days worked, and runs of consecutive days
  sh.getRange('AG1:AI1').setValues([['day', 'new run', 'run']]);
  sh.getRange('AG2').setFormula('=IFERROR(SORT(UNIQUE(FILTER(V2:V, V2:V <> ""))), )');
  sh.getRange('AH2').setFormula('=ARRAYFORMULA(IF(AG2:AG = "", , IF(ROW(AG2:AG) = 2, 1, IF(AG2:AG - AG1:AG19999 = 1, 0, 1))))');
  sh.getRange('AI2').setFormula('=ARRAYFORMULA(IF(AG2:AG = "", , SCAN(0, AH2:AH, LAMBDA(a, x, a + N(x)))))');

  // Records. Each query returns one row.
  const q = (cell, query) => sh.getRange(cell).setFormula('=IFERROR(QUERY(V2:AC, "' + query + '", 0), )');
  sh.getRange('AK1').setValue('records');
  q('AK2', "select Z, W, V where V is not null order by Z desc limit 1 label Z '', W '', V ''");                      // longest session: hours, label, day
  q('AK3', "select V, sum(Z) where V is not null group by V order by sum(Z) desc limit 1 label V '', sum(Z) ''");      // longest day: day, hours
  q('AK4', "select AB, sum(Z) where V is not null group by AB order by sum(Z) desc limit 1 label AB '', sum(Z) ''");   // best week: week, hours
  q('AK5', "select V, sum(AA) where V is not null group by V order by sum(AA) desc limit 1 label V '', sum(AA) ''");   // most pomodoros in a day: day, count
  q('AK6', "select W, count(W) where V is not null group by W order by count(W) desc limit 1 label W '', count(W) ''"); // most sessions on one label: label, count
  q('AK7', "select W, sum(Z) where V is not null group by W order by sum(Z) desc limit 1 label W '', sum(Z) ''");      // most time on one label: label, hours
  q('AK8', "select AC, sum(Z) where V is not null group by AC order by sum(Z) desc limit 1 label AC '', sum(Z) ''");   // best month: month, hours
  sh.getRange('AK9').setFormula('=IFERROR(QUERY(AI2:AI, "select count(AI) where AI is not null group by AI order by count(AI) desc limit 1 label count(AI) \'\'", 0), 0)'); // longest streak, days

  ['A2:A', 'G2:H', 'M2:M', 'S2:T', 'V2:V', 'AB2:AC', 'AE2:AE3', 'AG2:AG'].forEach(a => sh.getRange(a).setNumberFormat('yyyy-mm-dd'));
  sh.hideSheet();
}

// ---- dashboard --------------------------------------------------------------------

function buildDash_(ss, sh, keepView, keepDates) {
  sh.clear();
  fit_(sh, 1000, 21);
  const all = sh.getRange(1, 1, sh.getMaxRows(), sh.getMaxColumns());
  all.clearDataValidations();
  all.setFontFamily(FONT).setFontSize(10).setFontColor(INK).setBackground('#ffffff').setVerticalAlignment('middle');
  sh.setHiddenGridlines(true);

  const widths = { A: 24, B: 210, C: 130, D: 90, E: 80, F: 130, G: 80, H: 130, I: 110, J: 90, K: 130, L: 28, M: 110, N: 70, O: 90, P: 130, Q: 28, R: 200, S: 120, T: 240 };
  Object.keys(widths).forEach(c => sh.setColumnWidth(c.charCodeAt(0) - 64, widths[c]));

  // Title and controls
  sh.getRange('B2').setValue('tally').setFontSize(18).setFontWeight('bold');
  sh.getRange('B3').setValue('view');
  sh.getRange('B4').setValue('category');
  const view = sh.getRange('C3');
  const cat = sh.getRange('C4');
  view.setValue(keepView && keepView[0][0] ? keepView[0][0] : 'this week');
  cat.setValue(keepView && keepView[1][0] ? keepView[1][0] : 'all');
  view.setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(VIEWS, true).build());
  cat.setDataValidation(SpreadsheetApp.newDataValidation()
    .requireValueInRange(ss.getSheetByName(CALC).getRange('J2:J'), true).build());
  [view, cat].forEach(r => r.setFontWeight('bold')
    .setBorder(true, true, true, true, null, null, INK, SpreadsheetApp.BorderStyle.SOLID));
  sh.getRange('B5').setFormula('=LOWER(TEXT(calc!AE2, "d mmm yyyy") & " – " & TEXT(calc!AE3, "d mmm yyyy"))')
    .setFontColor(MUTED);

  // Custom dates, used when view is "pick dates"
  const today = new Date();
  sh.getRange('H3').setValue('pick dates, from').setHorizontalAlignment('right').setFontColor(MUTED);
  sh.getRange('H4').setValue('to').setHorizontalAlignment('right').setFontColor(MUTED);
  const from = sh.getRange('I3');
  const to = sh.getRange('I4');
  from.setValue(keepDates && keepDates[0][0] ? keepDates[0][0] : new Date(today.getFullYear(), today.getMonth(), 1));
  to.setValue(keepDates && keepDates[1][0] ? keepDates[1][0] : today);
  [from, to].forEach(r => r.setNumberFormat('d mmm yyyy')
    .setDataValidation(SpreadsheetApp.newDataValidation().requireDate().build())
    .setBorder(null, null, true, null, null, null, INK, SpreadsheetApp.BorderStyle.DOTTED));

  // Totals for the view
  const stats = [
    ['B', 'hours', '=ROUND(SUM(calc!Q2:Q), 1)'],
    ['D', 'pomodoros', '=SUM(calc!R2:R)'],
    ['F', 'days worked', '=COUNTUNIQUE(calc!M2:M)'],
    ['H', 'hours a day', '=IFERROR(ROUND(SUM(calc!Q2:Q) / COUNTUNIQUE(calc!M2:M), 1), 0)'],
    ['J', 'most time on', '=IFERROR(INDEX(QUERY(calc!M2:T, "select O, sum(Q) where M is not null group by O order by sum(Q) desc limit 1 label O \'\', sum(Q) \'\'", 0), 1, 1), "–")'],
  ];
  stats.forEach(([c, label, f]) => {
    sh.getRange(c + '7').setValue(label).setFontColor(MUTED);
    sh.getRange(c + '8').setFormula(f).setFontSize(24).setHorizontalAlignment('left');
  });
  sh.getRange('J8').setFontSize(14).setFontWeight('bold');
  sh.setRowHeight(8, 40);
  sh.getRange('B9:T9').setBorder(null, null, true, null, null, null, INK, SpreadsheetApp.BorderStyle.SOLID);

  // By category (view)
  section_(sh, 11, 2, 'by category', ['category', 'hours', 'pomodoros', 'share', '']);
  sh.getRange('B13').setFormula('=IFERROR(QUERY(calc!M2:T, "select O, sum(Q), sum(R) where M is not null group by O order by sum(Q) desc limit 12 label O \'\', sum(Q) \'\', sum(R) \'\'", 0), )');
  for (let r = 13; r <= 24; r++) {
    sh.getRange('E' + r).setFormula('=IF(B' + r + ' = "", "", C' + r + ' / SUM($C$13:$C$24))');
    sh.getRange('F' + r).setFormula(bar_('C' + r, '$C$13:$C$24', 'B' + r));
  }
  sh.getRange('C13:C24').setNumberFormat('0.0');
  sh.getRange('E13:E24').setNumberFormat('0%');
  dotted_(sh, 13, 2, 12, 5);

  // By label (view)
  section_(sh, 27, 2, 'by label', ['label', 'category', 'hours', 'pomodoros', 'first', 'last']);
  sh.getRange('B29').setFormula('=IFERROR(QUERY(calc!M2:T, "select N, O, sum(Q), sum(R), min(M), max(M) where M is not null group by N, O order by sum(Q) desc label N \'\', O \'\', sum(Q) \'\', sum(R) \'\', min(M) \'\', max(M) \'\'", 0), )');
  sh.getRange('D29:D1000').setNumberFormat('0.0');
  sh.getRange('F29:G1000').setNumberFormat('d mmm yyyy');
  dotted_(sh, 29, 2, 40, 6);

  // By day (view)
  section_(sh, 11, 8, 'by day', ['day', 'hours', 'pomodoros', '']);
  sh.getRange('H13').setFormula('=IFERROR(QUERY(calc!M2:T, "select M, sum(Q), sum(R) where M is not null group by M order by M label M \'\', sum(Q) \'\', sum(R) \'\'", 0), )');
  sh.getRange('H13:H1000').setNumberFormat('ddd d mmm');
  sh.getRange('I13:I1000').setNumberFormat('0.0');
  for (let r = 13; r <= 43; r++) sh.getRange('K' + r).setFormula(bar_('I' + r, '$I$13:$I$43', 'H' + r));
  dotted_(sh, 13, 8, 31, 4);

  // Last 12 weeks (category only, ignores view)
  section_(sh, 11, 13, 'last 12 weeks', ['week of', 'hours', 'pomodoros', '']);
  sh.getRange('M13').setFormula('=ARRAYFORMULA(TODAY() - WEEKDAY(TODAY(), 3) - 7 * SEQUENCE(12, 1, 11, -1))');
  sh.getRange('N13').setFormula('=ARRAYFORMULA(ROUND(SUMIF(calc!AB2:AB, M13:M24, calc!Z2:Z), 1))');
  sh.getRange('O13').setFormula('=ARRAYFORMULA(SUMIF(calc!AB2:AB, M13:M24, calc!AA2:AA))');
  for (let r = 13; r <= 24; r++) sh.getRange('P' + r).setFormula(bar_('N' + r, '$N$13:$N$24', 'M' + r));
  sh.getRange('M13:M24').setNumberFormat('d mmm');
  sh.getRange('N13:N24').setNumberFormat('0.0');
  dotted_(sh, 13, 13, 12, 4);

  // Last 12 months (category only, ignores view)
  section_(sh, 27, 13, 'last 12 months', ['month', 'hours', 'pomodoros', '']);
  sh.getRange('M29').setFormula('=ARRAYFORMULA(DATE(YEAR(TODAY()), MONTH(TODAY()) + SEQUENCE(12, 1, -11, 1), 1))');
  sh.getRange('N29').setFormula('=ARRAYFORMULA(ROUND(SUMIF(calc!AC2:AC, M29:M40, calc!Z2:Z), 1))');
  sh.getRange('O29').setFormula('=ARRAYFORMULA(SUMIF(calc!AC2:AC, M29:M40, calc!AA2:AA))');
  for (let r = 29; r <= 40; r++) sh.getRange('P' + r).setFormula(bar_('N' + r, '$N$29:$N$40', 'M' + r));
  sh.getRange('M29:M40').setNumberFormat('mmm yyyy');
  sh.getRange('N29:N40').setNumberFormat('0.0');
  dotted_(sh, 29, 13, 12, 4);

  sh.getRange('M42').setValue('the two trend tables follow the category, not the view.').setFontColor(MUTED).setFontSize(9);

  // Records (category only, all time)
  section_(sh, 11, 18, 'records', ['record', '', '']);
  const day = c => 'LOWER(TEXT(' + c + ', "ddd d mmm yyyy"))';
  const records = [
    ['longest session', 'ROUND(calc!AK2, 1) & " h"', 'calc!AL2 & ", " & ' + day('calc!AM2'), 'calc!AK2'],
    ['longest day', 'ROUND(calc!AL3, 1) & " h"', day('calc!AK3'), 'calc!AK3'],
    ['most pomodoros in a day', 'calc!AL5', day('calc!AK5'), 'calc!AK5'],
    ['best week', 'ROUND(calc!AL4, 1) & " h"', '"week of " & LOWER(TEXT(calc!AK4, "d mmm yyyy"))', 'calc!AK4'],
    ['best month', 'ROUND(calc!AL8, 1) & " h"', 'LOWER(TEXT(calc!AK8, "mmmm yyyy"))', 'calc!AK8'],
    ['most sessions, one label', 'calc!AL6 & " sessions"', 'calc!AK6', 'calc!AK6'],
    ['most time, one label', 'ROUND(calc!AL7, 1) & " h"', 'calc!AK7', 'calc!AK7'],
    ['longest streak', 'calc!AK9 & IF(calc!AK9 = 1, " day", " days in a row")', '""', 'calc!AK9'],
  ];
  records.forEach(([name, value, detail, key], i) => {
    const r = 13 + i;
    sh.getRange('R' + r).setValue(name);
    sh.getRange('S' + r).setFormula('=IF(OR(' + key + ' = "", ' + key + ' = 0), "–", ' + value + ')').setFontWeight('bold');
    sh.getRange('T' + r).setFormula('=IF(OR(' + key + ' = "", ' + key + ' = 0), "", ' + detail + ')').setFontColor(MUTED);
  });
  dotted_(sh, 13, 18, records.length, 3);
  sh.getRange('R' + (13 + records.length + 1)).setValue('records are all time and follow the category, not the view.')
    .setFontColor(MUTED).setFontSize(9);
}

// ---- helpers ----------------------------------------------------------------------

function section_(sh, row, col, title, headers) {
  sh.getRange(row, col).setValue(title).setFontWeight('bold').setFontSize(11);
  sh.getRange(row + 1, col, 1, headers.length).setValues([headers]).setFontColor(MUTED)
    .setBorder(null, null, true, null, null, null, INK, SpreadsheetApp.BorderStyle.SOLID);
}

function dotted_(sh, row, col, rows, cols) {
  sh.getRange(row, col, rows, cols)
    .setBorder(null, null, true, null, null, true, INK, SpreadsheetApp.BorderStyle.DOTTED);
}

/** Black bar sized against the biggest value in its column. */
function bar_(valueCell, range, keyCell) {
  return '=IF(' + keyCell + ' = "", "", IFERROR(SPARKLINE(' + valueCell +
    ', {"charttype", "bar"; "max", MAX(' + range + '); "color1", "black"}), ""))';
}

function fit_(sh, rows, cols) {
  if (sh.getMaxRows() < rows) sh.insertRowsAfter(sh.getMaxRows(), rows - sh.getMaxRows());
  if (sh.getMaxColumns() < cols) sh.insertColumnsAfter(sh.getMaxColumns(), cols - sh.getMaxColumns());
}
"""#
}
