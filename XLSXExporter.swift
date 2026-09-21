import Foundation

/// Сборка .xlsx вручную (ZIP без сжатия + OOXML), без сторонних библиотек.
/// Алгоритм сверен с Python-портом: файл проходит проверку zipfile и открывается
/// в openpyxl и LibreOffice.
nonisolated enum XLSXExporter {

    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            t[n] = c
        }
        return t
    }()

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(b)) & 0xFF)]
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func escXml(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func colLetter(_ n: Int) -> String {
        var result = ""
        var num = n
        while num > 0 {
            let rem = (num - 1) % 26
            result = String(UnicodeScalar(UInt8(65 + rem))) + result
            num = (num - 1) / 26
        }
        return result
    }

    private struct ZipFile {
        var name: String
        var data: [UInt8]
    }

    private static func appendUInt16(_ v: UInt16, to arr: inout [UInt8]) {
        arr.append(UInt8(v & 0xFF))
        arr.append(UInt8((v >> 8) & 0xFF))
    }
    private static func appendUInt32(_ v: UInt32, to arr: inout [UInt8]) {
        arr.append(UInt8(v & 0xFF))
        arr.append(UInt8((v >> 8) & 0xFF))
        arr.append(UInt8((v >> 16) & 0xFF))
        arr.append(UInt8((v >> 24) & 0xFF))
    }

    private static func makeZip(_ files: [ZipFile]) -> Data {
        var localParts: [UInt8] = []
        var centralParts: [UInt8] = []
        var offset: UInt32 = 0

        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let dosTime: UInt16 = UInt16((((comps.hour ?? 0) & 0x1F) << 11) | (((comps.minute ?? 0) & 0x3F) << 5) | (((comps.second ?? 0) / 2) & 0x1F))
        let dosDate: UInt16 = UInt16(((((comps.year ?? 1980) - 1980) & 0x7F) << 9) | (((comps.month ?? 1) & 0x0F) << 5) | ((comps.day ?? 1) & 0x1F))

        for file in files {
            let nameBytes = Array(file.name.utf8)
            let fdata = file.data
            let crc = crc32(fdata)
            let size = UInt32(fdata.count)

            var local: [UInt8] = []
            appendUInt32(0x04034b50, to: &local)
            appendUInt16(20, to: &local)
            appendUInt16(0, to: &local)
            appendUInt16(0, to: &local)
            appendUInt16(dosTime, to: &local)
            appendUInt16(dosDate, to: &local)
            appendUInt32(crc, to: &local)
            appendUInt32(size, to: &local)
            appendUInt32(size, to: &local)
            appendUInt16(UInt16(nameBytes.count), to: &local)
            appendUInt16(0, to: &local)
            local.append(contentsOf: nameBytes)

            localParts.append(contentsOf: local)
            localParts.append(contentsOf: fdata)

            var central: [UInt8] = []
            appendUInt32(0x02014b50, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(dosTime, to: &central)
            appendUInt16(dosDate, to: &central)
            appendUInt32(crc, to: &central)
            appendUInt32(size, to: &central)
            appendUInt32(size, to: &central)
            appendUInt16(UInt16(nameBytes.count), to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(0, to: &central)
            appendUInt32(offset, to: &central)
            central.append(contentsOf: nameBytes)

            centralParts.append(contentsOf: central)
            offset += UInt32(local.count) + size
        }

        let centralOffset = offset
        let centralSize = UInt32(centralParts.count)

        var end: [UInt8] = []
        appendUInt32(0x06054b50, to: &end)
        appendUInt16(0, to: &end)
        appendUInt16(0, to: &end)
        appendUInt16(UInt16(files.count), to: &end)
        appendUInt16(UInt16(files.count), to: &end)
        appendUInt32(centralSize, to: &end)
        appendUInt32(centralOffset, to: &end)
        appendUInt16(0, to: &end)

        var result: [UInt8] = []
        result.append(contentsOf: localParts)
        result.append(contentsOf: centralParts)
        result.append(contentsOf: end)
        return Data(result)
    }

    static func buildXLSX(operations: [OperationRecord]) -> Data {
        let headers = ["Дата", "Время", "Банк", "Счёт", "Операция", "Категория", "Подкатегория", "Лицо", "Сумма", "Комментарий"]
        var rowsXml: [String] = []

        var headerCells = ""
        for (i, h) in headers.enumerated() {
            headerCells += "<c r=\"\(colLetter(i + 1))1\" t=\"inlineStr\" s=\"1\"><is><t>\(escXml(h))</t></is></c>"
        }
        rowsXml.append("<row r=\"1\">\(headerCells)</row>")

        for (idx, rec) in operations.enumerated() {
            let r = idx + 2
            let vals: [String?] = [rec.date, rec.time, rec.bank, rec.account, rec.operation, rec.category, rec.subcategory, rec.person, nil, rec.comment]
            var cells = ""
            for (i, v) in vals.enumerated() {
                let cellRef = "\(colLetter(i + 1))\(r)"
                if i == 8 {
                    // Число с 2 знаками после точки (формат XML всегда с точкой),
                    // стиль 2 = "# ##0,00" — в Excel видно как денежная сумма
                    let amountStr = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rec.amount)
                    cells += "<c r=\"\(cellRef)\" s=\"2\"><v>\(amountStr)</v></c>"
                } else {
                    cells += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escXml(v ?? ""))</t></is></c>"
                }
            }
            rowsXml.append("<row r=\"\(r)\">\(cells)</row>")
        }

        let lastRow = operations.count + 1

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        let workbookXml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Операции" sheetId="1" r:id="rId1"/></sheets>
        <definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'Операции'!$A$1:$J$\(lastRow)</definedName></definedNames>
        </workbook>
        """

        let stylesXml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="3">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        <xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """

        let sheetXml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <dimension ref="A1:J\(lastRow)"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <cols>
        <col min="1" max="1" width="12" customWidth="1"/>
        <col min="2" max="2" width="8" customWidth="1"/>
        <col min="3" max="4" width="15" customWidth="1"/>
        <col min="5" max="5" width="12" customWidth="1"/>
        <col min="6" max="7" width="16" customWidth="1"/>
        <col min="8" max="8" width="20" customWidth="1"/>
        <col min="9" max="9" width="12" customWidth="1"/>
        <col min="10" max="10" width="32" customWidth="1"/>
        </cols>
        <sheetData>
        \(rowsXml.joined(separator: "\n"))
        </sheetData>
        <autoFilter ref="A1:J\(lastRow)"/>
        </worksheet>
        """

        let files: [ZipFile] = [
            ZipFile(name: "[Content_Types].xml", data: Array(contentTypes.utf8)),
            ZipFile(name: "_rels/.rels", data: Array(rootRels.utf8)),
            ZipFile(name: "xl/workbook.xml", data: Array(workbookXml.utf8)),
            ZipFile(name: "xl/_rels/workbook.xml.rels", data: Array(workbookRels.utf8)),
            ZipFile(name: "xl/styles.xml", data: Array(stylesXml.utf8)),
            ZipFile(name: "xl/worksheets/sheet1.xml", data: Array(sheetXml.utf8)),
        ]

        return makeZip(files)
    }
}
