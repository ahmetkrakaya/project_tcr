import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Hücre görünümleri. Sıralama styles.xml içindeki `cellXfs` sırasıyla birebir
/// eşleşmek zorundadır.
enum XlsxStyle {
  normal,
  bold,
  title,
  subtitle,
  sectionHeader,
  columnHeader,
  text,
  textBold,
  label,
  money,
  moneyBold,
  moneyHighlight,
  integer,
  integerBold,
  date,
  center,
}

class _XlsxCell {
  final Object? value;
  final XlsxStyle style;

  const _XlsxCell(this.value, this.style);
}

class _XlsxMerge {
  final int firstRow;
  final int firstCol;
  final int lastRow;
  final int lastCol;

  const _XlsxMerge(this.firstRow, this.firstCol, this.lastRow, this.lastCol);
}

/// Tek bir çalışma sayfası. Hücreler seyrek (sparse) tutulur; böylece aynı
/// sayfada yan yana duran tablolar arasındaki boşluklar yer kaplamaz.
class XlsxSheet {
  XlsxSheet(this.name);

  final String name;
  final Map<int, Map<int, _XlsxCell>> _rows = {};
  final Map<int, double> _columnWidths = {};
  final List<_XlsxMerge> _merges = [];
  int _frozenRows = 0;
  int _frozenCols = 0;

  void setColumnWidth(int col, double width) => _columnWidths[col] = width;

  void setColumnWidths(Map<int, double> widths) =>
      _columnWidths.addAll(widths);

  void freeze({int rows = 0, int cols = 0}) {
    _frozenRows = rows;
    _frozenCols = cols;
  }

  void setText(
    int row,
    int col,
    String? value, {
    XlsxStyle style = XlsxStyle.normal,
  }) {
    final trimmed = (value == null || value.isEmpty) ? null : value;
    _set(row, col, trimmed, style);
  }

  void setNumber(
    int row,
    int col,
    num? value, {
    XlsxStyle style = XlsxStyle.normal,
  }) {
    _set(row, col, value, style);
  }

  void setDate(
    int row,
    int col,
    DateTime? value, {
    XlsxStyle style = XlsxStyle.date,
  }) {
    _set(row, col, value, style);
  }

  void setBlank(int row, int col, {XlsxStyle style = XlsxStyle.normal}) {
    _set(row, col, null, style);
  }

  /// [row] satırındaki [col] sütunundan başlayarak verilen aralığı birleştirir.
  void merge(int row, int col, {int colSpan = 1, int rowSpan = 1}) {
    if (colSpan <= 1 && rowSpan <= 1) return;
    final lastRow = row + rowSpan - 1;
    final lastCol = col + colSpan - 1;
    // Birleştirilen alandaki tüm hücreler var olmalı, yoksa kenarlıklar eksik çizilir.
    final style = _rows[row]?[col]?.style ?? XlsxStyle.normal;
    for (var r = row; r <= lastRow; r++) {
      for (var c = col; c <= lastCol; c++) {
        if (r == row && c == col) continue;
        if (_rows[r]?[c] == null) _set(r, c, null, style);
      }
    }
    _merges.add(_XlsxMerge(row, col, lastRow, lastCol));
  }

  void _set(int row, int col, Object? value, XlsxStyle style) {
    _rows.putIfAbsent(row, () => {})[col] = _XlsxCell(value, style);
  }

  String _toXml() {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main">');

    buffer.write('<dimension ref="${_dimensionRef()}"/>');
    buffer.write(_sheetViewsXml());

    if (_columnWidths.isNotEmpty) {
      buffer.write('<cols>');
      final cols = _columnWidths.keys.toList()..sort();
      for (final col in cols) {
        buffer.write('<col min="${col + 1}" max="${col + 1}" '
            'width="${_columnWidths[col]}" customWidth="1"/>');
      }
      buffer.write('</cols>');
    }

    buffer.write('<sheetData>');
    final rowIndexes = _rows.keys.toList()..sort();
    for (final rowIndex in rowIndexes) {
      final cells = _rows[rowIndex]!;
      final colIndexes = cells.keys.toList()..sort();
      buffer.write('<row r="${rowIndex + 1}">');
      for (final colIndex in colIndexes) {
        buffer.write(_cellXml(rowIndex, colIndex, cells[colIndex]!));
      }
      buffer.write('</row>');
    }
    buffer.write('</sheetData>');

    if (_merges.isNotEmpty) {
      buffer.write('<mergeCells count="${_merges.length}">');
      for (final m in _merges) {
        final ref = '${_ref(m.firstRow, m.firstCol)}:'
            '${_ref(m.lastRow, m.lastCol)}';
        buffer.write('<mergeCell ref="$ref"/>');
      }
      buffer.write('</mergeCells>');
    }

    buffer.write('</worksheet>');
    return buffer.toString();
  }

  String _sheetViewsXml() {
    if (_frozenRows == 0 && _frozenCols == 0) {
      return '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';
    }
    final topLeft = _ref(_frozenRows, _frozenCols);
    final pane = StringBuffer('<pane ');
    if (_frozenCols > 0) pane.write('xSplit="$_frozenCols" ');
    if (_frozenRows > 0) pane.write('ySplit="$_frozenRows" ');
    pane.write('topLeftCell="$topLeft" activePane="bottomRight" '
        'state="frozen"/>');
    return '<sheetViews><sheetView workbookViewId="0">$pane'
        '</sheetView></sheetViews>';
  }

  String _dimensionRef() {
    if (_rows.isEmpty) return 'A1';
    var maxRow = 0;
    var maxCol = 0;
    for (final entry in _rows.entries) {
      if (entry.key > maxRow) maxRow = entry.key;
      for (final col in entry.value.keys) {
        if (col > maxCol) maxCol = col;
      }
    }
    return 'A1:${_ref(maxRow, maxCol)}';
  }

  String _cellXml(int row, int col, _XlsxCell cell) {
    final ref = _ref(row, col);
    final styleIndex = cell.style.index;
    final value = cell.value;

    if (value == null) {
      return '<c r="$ref" s="$styleIndex"/>';
    }
    if (value is num) {
      if (value.isNaN || value.isInfinite) {
        return '<c r="$ref" s="$styleIndex"/>';
      }
      return '<c r="$ref" s="$styleIndex"><v>${_numToString(value)}</v></c>';
    }
    if (value is DateTime) {
      return '<c r="$ref" s="$styleIndex"><v>${_excelSerialDate(value)}</v></c>';
    }
    final text = _escape(value.toString());
    return '<c r="$ref" s="$styleIndex" t="inlineStr">'
        '<is><t xml:space="preserve">$text</t></is></c>';
  }
}

/// Birden fazla sekmeden oluşan bir .xlsx dosyası üretir.
///
/// Sadece ihtiyaç duyulan OOXML parçaları yazılır (workbook, styles, sheets);
/// harici bir Excel paketine bağımlılık yoktur.
class XlsxWorkbook {
  final List<XlsxSheet> _sheets = [];

  XlsxSheet addSheet(String name) {
    final sheet = XlsxSheet(_uniqueSheetName(name));
    _sheets.add(sheet);
    return sheet;
  }

  Uint8List encode() {
    if (_sheets.isEmpty) addSheet('Sayfa1');

    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypesXml()))
      ..add(ArchiveFile.string('_rels/.rels', _rootRelsXml()))
      ..add(ArchiveFile.string('xl/workbook.xml', _workbookXml()))
      ..add(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRelsXml()))
      ..add(ArchiveFile.string('xl/styles.xml', _stylesXml()));

    for (var i = 0; i < _sheets.length; i++) {
      archive.add(
        ArchiveFile.string('xl/worksheets/sheet${i + 1}.xml', _sheets[i]._toXml()),
      );
    }

    return ZipEncoder().encodeBytes(archive);
  }

  String _uniqueSheetName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (name.isEmpty) name = 'Sayfa';
    if (name.length > 31) name = name.substring(0, 31).trim();

    final existing = _sheets.map((s) => s.name.toLowerCase()).toSet();
    if (!existing.contains(name.toLowerCase())) return name;

    for (var i = 2; i < 1000; i++) {
      final suffix = ' ($i)';
      final base = name.length + suffix.length > 31
          ? name.substring(0, 31 - suffix.length).trim()
          : name;
      final candidate = '$base$suffix';
      if (!existing.contains(candidate.toLowerCase())) return candidate;
    }
    return name;
  }

  String _contentTypesXml() {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types">')
      ..write('<Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/'
          'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 0; i < _sheets.length; i++) {
      buffer.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.worksheet+xml"/>');
    }
    buffer.write('</Types>');
    return buffer.toString();
  }

  String _rootRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '</Relationships>';
  }

  String _workbookXml() {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/'
          'spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/'
          'officeDocument/2006/relationships"><sheets>');
    for (var i = 0; i < _sheets.length; i++) {
      buffer.write('<sheet name="${_escape(_sheets[i].name)}" '
          'sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    buffer.write('</sheets></workbook>');
    return buffer.toString();
  }

  String _workbookRelsXml() {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/'
          'package/2006/relationships">');
    for (var i = 0; i < _sheets.length; i++) {
      buffer.write('<Relationship Id="rId${i + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
          'relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
    }
    buffer.write('<Relationship Id="rId${_sheets.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/styles" Target="styles.xml"/>');
    buffer.write('</Relationships>');
    return buffer.toString();
  }

  String _stylesXml() {
    const money = 164;
    const dateFmt = 165;
    const intFmt = 3; // yerleşik #,##0

    String xf(
      int numFmt,
      int font,
      int fill,
      int border, {
      String? align,
    }) {
      final buffer = StringBuffer('<xf numFmtId="$numFmt" fontId="$font" '
          'fillId="$fill" borderId="$border" xfId="0"'
          ' applyNumberFormat="1" applyFont="1" applyFill="1" '
          'applyBorder="1"');
      if (align != null) {
        buffer.write(' applyAlignment="1"><alignment $align/></xf>');
      } else {
        buffer.write('/>');
      }
      return buffer.toString();
    }

    const centered = 'horizontal="center" vertical="center"';
    const headerAlign =
        'horizontal="center" vertical="center" wrapText="1"';

    final cellXfs = <String>[
      xf(0, 0, 0, 0), // normal
      xf(0, 1, 0, 0), // bold
      xf(0, 2, 0, 0, align: 'vertical="center"'), // title
      xf(0, 3, 0, 0), // subtitle
      xf(0, 4, 2, 1, align: centered), // sectionHeader
      xf(0, 4, 2, 1, align: headerAlign), // columnHeader
      xf(0, 0, 0, 1, align: 'vertical="center"'), // text
      xf(0, 1, 0, 1, align: 'vertical="center"'), // textBold
      xf(0, 1, 3, 1, align: 'vertical="center"'), // label
      xf(money, 0, 0, 1), // money
      xf(money, 1, 0, 1), // moneyBold
      xf(money, 1, 4, 1), // moneyHighlight
      xf(intFmt, 0, 0, 1, align: centered), // integer
      xf(intFmt, 1, 0, 1, align: centered), // integerBold
      xf(dateFmt, 0, 0, 1, align: centered), // date
      xf(0, 0, 0, 1, align: centered), // center
    ];

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
        '2006/main">'
        '<numFmts count="2">'
        '<numFmt numFmtId="$money" formatCode="#,##0.00&quot; ₺&quot;"/>'
        '<numFmt numFmtId="$dateFmt" formatCode="dd\\.mm\\.yyyy"/>'
        '</numFmts>'
        '<fonts count="5">'
        '<font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="16"/><color rgb="FF1F4E79"/><name val="Calibri"/></font>'
        '<font><i/><sz val="10"/><color rgb="FF7F7F7F"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
        '</fonts>'
        '<fills count="5">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E79"/>'
        '<bgColor indexed="64"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFEDF2F9"/>'
        '<bgColor indexed="64"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/>'
        '<bgColor indexed="64"/></patternFill></fill>'
        '</fills>'
        '<borders count="2">'
        '<border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border>'
        '<left style="thin"><color rgb="FFBFBFBF"/></left>'
        '<right style="thin"><color rgb="FFBFBFBF"/></right>'
        '<top style="thin"><color rgb="FFBFBFBF"/></top>'
        '<bottom style="thin"><color rgb="FFBFBFBF"/></bottom>'
        '<diagonal/></border>'
        '</borders>'
        '<cellStyleXfs count="1">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
        '</cellStyleXfs>'
        '<cellXfs count="${cellXfs.length}">${cellXfs.join()}</cellXfs>'
        '<cellStyles count="1">'
        '<cellStyle name="Normal" xfId="0" builtinId="0"/>'
        '</cellStyles>'
        '</styleSheet>';
  }
}

String _ref(int row, int col) => '${_columnLetter(col)}${row + 1}';

String _columnLetter(int col) {
  var index = col;
  var letters = '';
  do {
    letters = String.fromCharCode(65 + (index % 26)) + letters;
    index = (index ~/ 26) - 1;
  } while (index >= 0);
  return letters;
}

String _numToString(num value) {
  if (value is int) return value.toString();
  final asDouble = value.toDouble();
  if (asDouble == asDouble.roundToDouble() && asDouble.abs() < 1e15) {
    return asDouble.toInt().toString();
  }
  return asDouble.toString();
}

/// Excel tarihleri 1899-12-30'dan itibaren gün sayısı olarak saklar.
int _excelSerialDate(DateTime date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  return utc.difference(DateTime.utc(1899, 12, 30)).inDays;
}

String _escape(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    // XML 1.0'da geçersiz olan kontrol karakterleri dosyayı bozar.
    if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) continue;
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
        break;
      case 0x3C:
        buffer.write('&lt;');
        break;
      case 0x3E:
        buffer.write('&gt;');
        break;
      case 0x22:
        buffer.write('&quot;');
        break;
      case 0x27:
        buffer.write('&apos;');
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
