import AppKit
import UniformTypeIdentifiers

enum ExportFormat {
    case csv, xlsx
    var ext: String { self == .csv ? "csv" : "xlsx" }
}

@MainActor
enum Exporter {
    static let header = ["Date", "Start", "End", "Label", "Type", "Minutes", "Completed", "Added min"]

    static func run(_ entries: [LogEntry], format: ExportFormat, name: String) {
        let rows = entries
            .filter { Prefs.includesBreaks || $0.phase == .work }
            .sorted { $0.start < $1.start }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(format.ext)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [
            format == .csv ? .commaSeparatedText : (UTType(filenameExtension: "xlsx") ?? .data)
        ]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data = format == .csv ? csv(rows) : xlsx(rows)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - CSV

    static func csv(_ rows: [LogEntry]) -> Data {
        var lines = [header.joined(separator: ",")]
        for e in rows {
            lines.append([
                Fmt.isoDay.string(from: e.start),
                Fmt.clock.string(from: e.start),
                Fmt.clock.string(from: e.end),
                csvField(e.label),
                e.phase.title,
                String(format: "%.1f", e.minutes),
                e.completed ? "Yes" : "No",
                String(e.addedMinutes),
            ].joined(separator: ","))
        }
        // BOM so Excel reads accented characters correctly.
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - XLSX

    enum Cell {
        case text(String, bold: Bool = false)
        case number(Double, style: Int)
    }

    // Style indexes into cellXfs below.
    private static let sDate = 1, sTime = 2, sOneDecimal = 4, sTwoDecimal = 5

    static func xlsx(_ rows: [LogEntry]) -> Data {
        var log: [[Cell]] = [header.map { Cell.text($0, bold: true) }]
        for e in rows {
            log.append([
                .number(serial(e.start).rounded(.down), style: sDate),
                .number(serial(e.start), style: sTime),
                .number(serial(e.end), style: sTime),
                .text(e.label),
                .text(e.phase.title),
                .number(e.minutes, style: sOneDecimal),
                .text(e.completed ? "Yes" : "No"),
                .number(Double(e.addedMinutes), style: 0),
            ])
        }

        var byLabel: [String: (label: String, count: Int, secs: Int)] = [:]
        for e in rows where e.phase == .work {
            let key = e.displayLabel.lowercased()
            var t: (label: String, count: Int, secs: Int) = byLabel[key] ?? (e.displayLabel, 0, 0)
            if e.completed { t.count += 1 }
            t.secs += e.seconds
            byLabel[key] = t
        }
        var totals: [[Cell]] = [["Label", "Pomodoros", "Minutes", "Hours"].map { Cell.text($0, bold: true) }]
        var allCount = 0, allSecs = 0
        for t in byLabel.values.sorted(by: { $0.secs > $1.secs }) {
            totals.append([
                .text(t.label),
                .number(Double(t.count), style: 0),
                .number(Double(t.secs) / 60, style: sOneDecimal),
                .number(Double(t.secs) / 3600, style: sTwoDecimal),
            ])
            allCount += t.count
            allSecs += t.secs
        }
        totals.append([
            .text("Total", bold: true),
            .number(Double(allCount), style: 0),
            .number(Double(allSecs) / 60, style: sOneDecimal),
            .number(Double(allSecs) / 3600, style: sTwoDecimal),
        ])

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("xl/workbook.xml", Data(workbook.utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8))
        zip.add("xl/styles.xml", Data(styles.utf8))
        zip.add("xl/worksheets/sheet1.xml", sheet(log, widths: [12, 8, 8, 40, 12, 10, 11, 10]))
        zip.add("xl/worksheets/sheet2.xml", sheet(totals, widths: [40, 11, 10, 10]))
        return zip.finish()
    }

    /// Excel date serial in local time.
    static func serial(_ d: Date) -> Double {
        let local = d.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: d))
        return local / 86400 + 25569
    }

    private static func sheet(_ rows: [[Cell]], widths: [Double]) -> Data {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        x += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        x += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
        x += "<cols>"
        for (i, w) in widths.enumerated() {
            x += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>"
        }
        x += "</cols><sheetData>"
        for (r, row) in rows.enumerated() {
            x += "<row r=\"\(r + 1)\">"
            for (c, cell) in row.enumerated() {
                let ref = column(c) + String(r + 1)
                switch cell {
                case .text(let s, let bold):
                    let style = bold ? " s=\"3\"" : ""
                    x += "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(s))</t></is></c>"
                case .number(let v, let s):
                    let style = s > 0 ? " s=\"\(s)\"" : ""
                    x += "<c r=\"\(ref)\"\(style)><v>\(v)</v></c>"
                }
            }
            x += "</row>"
        }
        x += "</sheetData></worksheet>"
        return Data(x.utf8)
    }

    private static func column(_ i: Int) -> String {
        String(Character(UnicodeScalar(UInt8(65 + i))))
    }

    private static func escape(_ s: String) -> String {
        let clean = String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }))
        return clean
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let contentTypes = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>"#

    private static let rootRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#

    private static let workbook = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Log" sheetId="1" r:id="rId1"/><sheet name="By label" sheetId="2" r:id="rId2"/></sheets></workbook>"#

    private static let workbookRels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#

    private static let styles = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="0.0"/><numFmt numFmtId="165" formatCode="0.00"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="20" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#
}
