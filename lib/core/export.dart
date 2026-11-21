import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_state.dart';
import 'desk.dart';
import 'reports.dart';
import 'util.dart';

/// Builds Excel / PDF files from a report and opens the phone's share sheet (save to Drive, send by WhatsApp or e-mail ...).
class Exporter {
  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  /// Asks where to save the file; returns the saved path (null = cancelled).
  static Future<String?> _share(List<int> bytes, String name, String mime) => Desk.saveBytes(name, bytes);

  static String _stamp() => dateStr(today());

  static List<int> excelBytes(ReportTable t, String subtitle) {
    final ex = Excel.createExcel();
    final def = ex.getDefaultSheet();
    final name = t.title.length > 28 ? t.title.substring(0, 28) : t.title;
    if (def != null) ex.rename(def, name);
    final sh = ex[name];
    sh.appendRow([TextCellValue('${AppState.instance.orgName} - ${t.title}')]);
    sh.appendRow([TextCellValue(subtitle)]);
    sh.appendRow([TextCellValue('')]);
    final head = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#7A5BF0'), fontColorHex: ExcelColor.white);
    const r0 = 3;
    for (var c = 0; c < t.headers.length; c++) {
      final cell = sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r0));
      cell.value = TextCellValue(t.headers[c]);
      cell.cellStyle = head;
      sh.setColumnWidth(c, 20);
    }
    for (final row in t.rows) {
      sh.appendRow([for (final v in row) TextCellValue(v)]);
    }
    if (t.footer.isNotEmpty) sh.appendRow([TextCellValue('')]);
    for (final f in t.footer) {
      sh.appendRow([TextCellValue(f)]);
    }
    return ex.encode()!;
  }

  static Future<String?> excel(ReportTable t, String subtitle) async =>
      _share(excelBytes(t, subtitle), '${_safe(t.title)}_${_stamp()}.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  static Future<List<int>> pdfBytes(ReportTable t, String subtitle) async {
    final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('${AppState.instance.orgName} - ${t.title}', style: pw.TextStyle(font: bold, fontSize: 15)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
      ]),
      footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
      build: (c) => [
        pw.TableHelper.fromTextArray(
          headers: t.headers,
          data: t.rows,
          headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF7A5BF0)),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F0FF)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        ),
        pw.SizedBox(height: 10),
        for (final f in t.footer) pw.Text(f, style: pw.TextStyle(font: bold, fontSize: 9)),
      ],
    ));
    return doc.save();
  }

  static Future<String?> pdf(ReportTable t, String subtitle) async => _share(await pdfBytes(t, subtitle), '${_safe(t.title)}_${_stamp()}.pdf', 'application/pdf');
}
