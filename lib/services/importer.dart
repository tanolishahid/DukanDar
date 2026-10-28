import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../format.dart';
import '../models.dart';

/// One product line ready to be added to the inventory.
class ImportRow {
  ImportRow({
    required this.line,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.model,
    required this.qty,
    required this.unitCost,
    required this.serial,
  });

  /// Line number in the user's file (for messages).
  final int line;
  final String name;
  final String category;
  final String subcategory;
  final String brand;
  final String model;
  final int qty;
  final double unitCost;
  final String serial;

  double get total => qty * unitCost;
}

class ImportResult {
  ImportResult({
    required this.batches,
    required this.newProducts,
    required this.units,
    required this.value,
    required this.skipped,
  });

  final int batches;
  final int newProducts;
  final int units;
  final double value;
  final List<String> skipped;
}

class ParsedTable {
  ParsedTable(this.headers, this.rows);

  final List<String> headers;
  final List<List<String>> rows;
}

class ConvertResult {
  ConvertResult(this.ok, this.problems);

  final List<ImportRow> ok;
  final List<String> problems;

  int get units => ok.fold<int>(0, (a, r) => a + r.qty);
  double get value => ok.fold<double>(0, (a, r) => a + r.total);
}

/// The things we look for in a file.
class ImportField {
  static const String name = 'name';
  static const String cost = 'cost';
  static const String qty = 'qty';
  static const String category = 'category';
  static const String brand = 'brand';
  static const String model = 'model';
  static const String serial = 'serial';

  static const List<String> all = [name, cost, qty, category, brand, model, serial];

  static const Map<String, String> labels = {
    name: 'Product name *',
    cost: 'Purchase price (each) *',
    qty: 'Quantity',
    category: 'Category / type',
    brand: 'Brand',
    model: 'Model',
    serial: 'Serial number',
  };

  static const Map<String, List<String>> synonyms = {
    name: [
      'product name',
      'item name',
      'product',
      'item',
      'name',
      'description',
      'particulars',
      'title',
    ],
    cost: [
      'purchase price',
      'purchasing price',
      'buying price',
      'buy price',
      'cost price',
      'unit cost',
      'purchase rate',
      'cost',
      'purchase',
      'rate',
      'price',
    ],
    qty: [
      'quantity',
      'qty',
      'stock',
      'in stock',
      'units',
      'pieces',
      'pcs',
      'count',
      'available',
    ],
    category: ['category', 'type', 'group', 'kind'],
    brand: ['brand', 'make', 'company', 'manufacturer'],
    model: ['model no', 'model number', 'model'],
    serial: ['serial number', 'serial no', 'serial', 'imei', 'sn'],
  };
}

class Importer {
  // --------------------------------------------------------------- reading

  /// Reads an .xlsx or .csv file. Throws a readable message on problems.
  static ParsedTable parse(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    List<List<String>> grid;
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      grid = _parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else if (lower.endsWith('.xlsx')) {
      grid = _parseExcel(bytes);
    } else if (lower.endsWith('.xls')) {
      throw 'Old .xls files are not supported. Open it in Excel and use '
          'Save As > Excel Workbook (.xlsx), then try again.';
    } else if (lower.endsWith('.pdf')) {
      throw 'PDF files cannot be read reliably. Open the PDF list in Excel or '
          'Google Sheets and save it as .xlsx or .csv, then try again.';
    } else {
      throw 'Please choose an Excel (.xlsx) or CSV (.csv) file.';
    }

    // Drop empty rows, find the header row (first row with 2+ filled cells).
    final rows = grid.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (rows.isEmpty) throw 'The file is empty.';
    var headerIndex = 0;
    for (var i = 0; i < rows.length && i < 10; i++) {
      if (rows[i].where((c) => c.trim().isNotEmpty).length >= 2) {
        headerIndex = i;
        break;
      }
    }
    final headers = rows[headerIndex].map((c) => c.trim()).toList();
    final data = rows.sublist(headerIndex + 1);
    if (data.isEmpty) throw 'The file has a header row but no products.';
    return ParsedTable(headers, data);
  }

  static List<List<String>> _parseExcel(Uint8List bytes) {
    Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (_) {
      throw 'This file could not be opened. Make sure it is a normal .xlsx file.';
    }
    for (final sheet in book.tables.values) {
      if (sheet.maxRows == 0) continue;
      final out = <List<String>>[];
      for (final row in sheet.rows) {
        out.add(row.map((cell) => _cellText(cell?.value)).toList());
      }
      return out;
    }
    throw 'No data found in the Excel file.';
  }

  static String _cellText(CellValue? v) {
    if (v == null) return '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
    }
    if (v is BoolCellValue) return v.value ? 'true' : 'false';
    try {
      final dynamic raw = (v as dynamic).value;
      if (raw is String) return raw;
      try {
        final dynamic t = raw.text;
        if (t is String) return t;
      } catch (_) {}
      return raw.toString();
    } catch (_) {
      return v.toString();
    }
  }

  static List<List<String>> _parseCsv(String input) {
    var text = input;
    if (text.startsWith('﻿')) text = text.substring(1);
    final firstLine = text.split('\n').first;
    var delim = ',';
    var best = -1;
    for (final d in [',', ';', '\t']) {
      final c = firstLine.split(d).length - 1;
      if (c > best) {
        best = c;
        delim = d;
      }
    }
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == delim) {
        row.add(field.toString());
        field = StringBuffer();
      } else if (c == '\n') {
        row.add(field.toString());
        rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else if (c != '\r') {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    return rows;
  }

  // -------------------------------------------------------------- matching

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Guesses which column is which. Returns field -> column index.
  static Map<String, int> autoMap(List<String> headers) {
    final norm = headers.map(_norm).toList();
    final used = <int>{};
    final map = <String, int>{};
    // exact matches first, then "contains"
    for (final pass in [0, 1]) {
      for (final field in ImportField.all) {
        if (map.containsKey(field)) continue;
        for (final syn in ImportField.synonyms[field]!) {
          var found = -1;
          for (var i = 0; i < norm.length; i++) {
            if (used.contains(i) || norm[i].isEmpty) continue;
            if (field == ImportField.cost &&
                RegExp(r'sell|sale|retail|mrp').hasMatch(norm[i])) {
              continue;
            }
            if (pass == 1 && syn.length < 4) continue;
            final hit = pass == 0 ? norm[i] == syn : norm[i].contains(syn);
            if (hit) {
              found = i;
              break;
            }
          }
          if (found >= 0) {
            map[field] = found;
            used.add(found);
            break;
          }
        }
      }
    }
    return map;
  }

  // ------------------------------------------------------------- converting

  static const List<String> _laptopWords = [
    'laptop',
    'notebook',
    'macbook',
    'thinkpad',
    'probook',
    'elitebook',
    'zbook',
    'ideapad',
    'inspiron',
    'vostro',
    'latitude',
    'vivobook',
    'zenbook',
    'pavilion',
    'chromebook',
    'aspire',
    'swift',
    'thinkbook',
    'legion',
    'victus',
    'omen',
    'tuf gaming',
  ];

  static const List<String> _computerWords = [
    'desktop',
    'all-in-one',
    'all in one',
    'mini pc',
    'gaming pc',
    'workstation',
    'optiplex',
    'prodesk',
    'thinkcentre',
    'imac',
    'mac mini',
  ];

  static String guessCategory(String name, String rawCategory) {
    final c = rawCategory.toLowerCase();
    if (c.contains('laptop') || c.contains('notebook')) return catLaptop;
    if (c.contains('computer') || c.contains('desktop') || c.trim() == 'pc') {
      return catComputer;
    }
    if (c.contains('access')) return catAccessory;
    final n = name.toLowerCase();
    for (final w in _laptopWords) {
      if (n.contains(w) || c.contains(w)) return catLaptop;
    }
    for (final w in _computerWords) {
      if (n.contains(w) || c.contains(w)) return catComputer;
    }
    return catAccessory;
  }

  static String guessComputerType(String name, String rawCategory) {
    final text = '${rawCategory.toLowerCase()} ${name.toLowerCase()}';
    bool has(List<String> words) => words.any(text.contains);
    if (has(['gaming'])) return 'Gaming PC';
    if (has(['all-in-one', 'all in one', 'imac', ' aio'])) return 'All-in-One';
    if (has(['mini pc', 'mac mini', 'nuc'])) return 'Mini PC';
    if (has(['workstation'])) return 'Workstation';
    if (has(['server'])) return 'Server';
    if (has(['desktop', 'optiplex', 'prodesk', 'thinkcentre'])) {
      return 'Desktop PC';
    }
    return 'Other';
  }

  static String guessSubcategory(String name, String rawCategory) {
    // If the Category column already holds one of our types (e.g. "LED",
    // "Graphic card"), trust it before guessing from the product name.
    final rawType = rawCategory.trim().toLowerCase();
    for (final t in accessoryTypes) {
      if (t != 'Other' && t.toLowerCase() == rawType) return t;
    }
    final text = '${rawCategory.toLowerCase()} ${name.toLowerCase()}';
    // Short words (led, ups, ram...) must match as whole words, so "handled"
    // or "groups" are not mistaken for LED / UPS.
    bool has(List<String> words) => words.any((w) {
          final pattern = w.length <= 4
              ? RegExp('\\b${RegExp.escape(w)}\\b')
              : RegExp('\\b${RegExp.escape(w)}');
          return pattern.hasMatch(text);
        });
    if (has(['keyboard'])) return 'Keyboard';
    if (has(['mouse', 'mice'])) return 'Mouse';
    if (has(['charger', 'adapter', 'adaptor'])) return 'Charger';
    if (has(['headphone', 'earphone', 'headset', 'earbud', 'airpod'])) {
      return 'Headphones';
    }
    if (has(['bag', 'backpack', 'sleeve'])) return 'Bag';
    if (has(['battery'])) return 'Battery';
    if (has(['graphic', 'graphics', 'gpu', 'video card', 'geforce', 'radeon', 'rtx', 'gtx'])) {
      return 'Graphic card';
    }
    if (has(['lcd', 'monitor'])) return 'LCD';
    if (has(['led'])) return 'LED';
    if (has(['processor', 'cpu', 'ryzen', 'core i3', 'core i5', 'core i7', 'core i9'])) {
      return 'Processor';
    }
    if (has(['motherboard', 'mainboard'])) return 'Motherboard';
    if (has(['power supply', 'psu', 'smps'])) return 'Power supply';
    if (has(['casing', 'case ', 'chassis'])) return 'Casing';
    if (has(['cooler', 'cooling', 'fan'])) return 'Cooler / Fan';
    if (has(['hdd', 'hard disk', 'hard drive'])) return 'HDD';
    if (has(['ram', 'ssd', 'memory', 'nvme', 'ddr3', 'ddr4', 'ddr5'])) return 'RAM / SSD';
    if (has(['printer', 'toner', 'cartridge'])) return 'Printer';
    if (has(['webcam', 'web cam'])) return 'Webcam';
    if (has(['speaker'])) return 'Speaker';
    if (has(['ups', 'inverter'])) return 'UPS';
    if (has(['router', 'wifi', 'wi-fi', 'lan card', 'switch'])) return 'Router / Network';
    if (has(['cable', 'hdmi', 'vga', 'usb hub', 'converter'])) return 'Cable / Adapter';
    final raw = rawCategory.trim();
    final r = raw.toLowerCase();
    if (raw.isNotEmpty &&
        r != 'accessory' &&
        r != 'accessories' &&
        r != 'laptop' &&
        r != 'laptops') {
      return raw[0].toUpperCase() + raw.substring(1);
    }
    return 'Other';
  }

  /// Turns the file rows into inventory lines using the chosen columns.
  static ConvertResult convert(ParsedTable table, Map<String, int> map) {
    final ok = <ImportRow>[];
    final problems = <String>[];

    String cell(List<String> row, String field) {
      final i = map[field];
      if (i == null || i < 0 || i >= row.length) return '';
      return row[i].trim();
    }

    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      final line = r + 2; // +1 for the header row, +1 to count from 1
      final name = cell(row, ImportField.name);
      if (name.isEmpty) {
        problems.add('Row $line: no product name');
        continue;
      }
      final cost = parseNum(cell(row, ImportField.cost));
      if (cost == null || cost < 0) {
        problems.add('Row $line ($name): purchase price is missing or not a number');
        continue;
      }
      var qty = 1;
      final qtyText = cell(row, ImportField.qty);
      if (map[ImportField.qty] != null && qtyText.isNotEmpty) {
        final q = parseNum(qtyText);
        if (q == null || q < 1) {
          problems.add('Row $line ($name): quantity must be 1 or more');
          continue;
        }
        qty = q.round();
      }
      final rawCategory = cell(row, ImportField.category);
      final category = guessCategory(name, rawCategory);
      final sub = category == catAccessory
          ? guessSubcategory(name, rawCategory)
          : category == catComputer
              ? guessComputerType(name, rawCategory)
              : '';
      var serial = cell(row, ImportField.serial);
      if (qty != 1) serial = '';
      ok.add(ImportRow(
        line: line,
        name: name,
        category: category,
        subcategory: sub,
        brand: cell(row, ImportField.brand),
        model: cell(row, ImportField.model),
        qty: qty,
        unitCost: cost,
        serial: serial,
      ));
    }
    return ConvertResult(ok, problems);
  }

  // --------------------------------------------------------------- template

  /// A small example file the shop owner can fill in.
  static List<int> template() {
    final book = Excel.createExcel();
    final first = book.getDefaultSheet();
    final sheet = book['Inventory'];
    sheet.appendRow([
      TextCellValue('Product name'),
      TextCellValue('Category'),
      TextCellValue('Brand'),
      TextCellValue('Model'),
      TextCellValue('Quantity'),
      TextCellValue('Purchase price'),
      TextCellValue('Serial number'),
    ]);
    sheet.appendRow([
      TextCellValue('ProBook 450 G8'),
      TextCellValue('Laptop'),
      TextCellValue('HP'),
      TextCellValue('450 G8'),
      IntCellValue(2),
      IntCellValue(65000),
      TextCellValue(''),
    ]);
    sheet.appendRow([
      TextCellValue('Wireless Mouse'),
      TextCellValue('Mouse'),
      TextCellValue('Logitech'),
      TextCellValue('M170'),
      IntCellValue(10),
      IntCellValue(900),
      TextCellValue(''),
    ]);
    if (first != null && first != 'Inventory') book.delete(first);
    book.setDefaultSheet('Inventory');
    return book.encode() ?? <int>[];
  }
}
