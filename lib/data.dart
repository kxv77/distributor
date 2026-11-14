import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'util.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int nowMs() => DateTime.now().millisecondsSinceEpoch;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

// ================================================================ models

class Shop {
  const Shop({required this.id, required this.name, this.phone = ''});
  final String id;
  final String name;
  final String phone;
  factory Shop.fromMap(Map<String, Object?> m) => Shop(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
      );
}

class Item {
  const Item({
    required this.id,
    required this.name,
    this.unit = 'كرتون',
    this.sellPrice = 0,
    this.costPrice = 0,
  });
  final String id;
  final String name;
  final String unit;
  final int sellPrice;
  final int costPrice;
  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        unit: (m['unit'] as String?) ?? 'كرتون',
        sellPrice: _i(m['sell_price']),
        costPrice: _i(m['cost_price']),
      );
}

/// سطر توزيع: صنف + كمية + السعر وقت التوزيع (لا يتغير لو تغير سعر الصنف بعدها)
class SaleLine {
  const SaleLine({
    required this.id,
    required this.shopId,
    required this.itemId,
    required this.date,
    required this.qty,
    required this.sellPrice,
    required this.costPrice,
    this.itemName = '',
    this.unit = '',
  });
  final String id, shopId, itemId, date;
  final double qty;
  final int sellPrice, costPrice;
  final String itemName, unit;

  int get total => (qty * sellPrice).round();
  int get cost => (qty * costPrice).round();

  factory SaleLine.fromMap(Map<String, Object?> m) => SaleLine(
        id: m['id'] as String,
        shopId: m['shop_id'] as String,
        itemId: m['item_id'] as String,
        date: m['date'] as String,
        qty: ((m['qty'] as num?) ?? 0).toDouble(),
        sellPrice: _i(m['sell_price']),
        costPrice: _i(m['cost_price']),
        itemName: (m['item_name'] as String?) ?? '',
        unit: (m['unit'] as String?) ?? '',
      );

  Map<String, Object?> toMap(int t) => {
        'id': id,
        'shop_id': shopId,
        'item_id': itemId,
        'date': date,
        'qty': qty,
        'sell_price': sellPrice,
        'cost_price': costPrice,
        'updated_at': t,
        'deleted': 0,
      };
}

class Payment {
  const Payment({required this.id, required this.shopId, required this.date, required this.amount});
  final String id, shopId, date;
  final int amount;
  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as String,
        shopId: m['shop_id'] as String,
        date: m['date'] as String,
        amount: _i(m['amount']),
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.note,
    required this.amount,
    required this.isIncome,
  });
  final String id, date, note;
  final int amount;
  final bool isIncome;
  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as String,
        date: m['date'] as String,
        note: (m['note'] as String?) ?? '',
        amount: _i(m['amount']),
        isIncome: _i(m['is_income']) == 1,
      );
}

class TraderPayment {
  const TraderPayment({required this.id, required this.date, required this.amount});
  final String id, date;
  final int amount;
  factory TraderPayment.fromMap(Map<String, Object?> m) => TraderPayment(
        id: m['id'] as String,
        date: m['date'] as String,
        amount: _i(m['amount']),
      );
}

// ================================================================ ledger

class DayInfo {
  DayInfo(this.date, this.total) : remaining = total;
  final String date;
  final int total;
  int remaining;
  int get paid => total - remaining;
}

/// حساب دكان واحد.
/// كل دفعة تُسدَّد من أحدث توزيع (حتى تاريخ الدفعة) ثم الأقدم،
/// وما زاد بعد انتهاء الديون يصير رصيداً له يُخصم من توزيعاته اللاحقة.
class ShopLedger {
  ShopLedger(this.days, this.totals, this.pays);
  final List<DayInfo> days; // تصاعدي بالتاريخ
  final Map<String, int> totals;
  final List<Payment> pays;

  int get totalSales => totals.values.fold(0, (a, b) => a + b);
  int get totalPaid => pays.fold(0, (a, x) => a + x.amount);

  /// موجب = عليه ، سالب = له
  int get balance => totalSales - totalPaid;

  DayInfo? day(String date) {
    for (final x in days) {
      if (x.date == date) return x;
    }
    return null;
  }

  /// الرصيد الإجمالي في نهاية يوم معيّن
  int balanceAt(String date) {
    var s = 0;
    totals.forEach((d, v) {
      if (d.compareTo(date) <= 0) s += v;
    });
    var p = 0;
    for (final x in pays) {
      if (x.date.compareTo(date) <= 0) p += x.amount;
    }
    return s - p;
  }
}

ShopLedger buildLedger(List<SaleLine> sales, List<Payment> pays) {
  final totals = <String, int>{};
  for (final s in sales) {
    totals[s.date] = (totals[s.date] ?? 0) + s.total;
  }
  final dates = totals.keys.toList()..sort();
  final days = [for (final d in dates) DayInfo(d, totals[d]!)];

  final ps = [...pays]..sort((a, b) => a.date.compareTo(b.date));
  final credits = <MapEntry<String, int>>[];

  for (final pay in ps) {
    var left = pay.amount;
    for (var i = days.length - 1; i >= 0 && left > 0; i--) {
      final d = days[i];
      if (d.date.compareTo(pay.date) > 0) continue;
      if (d.remaining <= 0) continue;
      final take = left < d.remaining ? left : d.remaining;
      d.remaining -= take;
      left -= take;
    }
    if (left > 0) credits.add(MapEntry(pay.date, left));
  }

  // الرصيد الزائد يُخصم من التوزيعات التي جاءت بعد تاريخ الدفعة
  for (final d in days) {
    for (var j = 0; j < credits.length && d.remaining > 0; j++) {
      final c = credits[j];
      if (c.value <= 0 || c.key.compareTo(d.date) >= 0) continue;
      final take = c.value < d.remaining ? c.value : d.remaining;
      d.remaining -= take;
      credits[j] = MapEntry(c.key, c.value - take);
    }
  }
  return ShopLedger(days, totals, pays);
}

// ================================================================ screens' data

class ShopsData {
  ShopsData(this.shops, this.ledgers, this.todaySales, this.todayPaid, this.paidToday);
  final List<Shop> shops;
  final Map<String, ShopLedger> ledgers;
  final int todaySales;
  final int todayPaid;
  final Map<String, int> paidToday;
  int get totalBalance => ledgers.values.fold(0, (a, l) => a + l.balance);
}

Future<ShopsData> loadShopsData() async {
  final shops = await Db.i.shops();
  final sales = await Db.i.allSales();
  final pays = await Db.i.allPayments();
  final bySales = <String, List<SaleLine>>{};
  final byPays = <String, List<Payment>>{};
  for (final s in sales) {
    (bySales[s.shopId] ??= []).add(s);
  }
  for (final x in pays) {
    (byPays[x.shopId] ??= []).add(x);
  }
  final ledgers = {
    for (final s in shops) s.id: buildLedger(bySales[s.id] ?? [], byPays[s.id] ?? []),
  };
  final today = ymd(DateTime.now());
  var todaySales = 0;
  var todayPaid = 0;
  final paidToday = <String, int>{};
  for (final s in shops) {
    for (final l in bySales[s.id] ?? <SaleLine>[]) {
      if (l.date == today) todaySales += l.total;
    }
    for (final x in byPays[s.id] ?? <Payment>[]) {
      if (x.date == today) {
        todayPaid += x.amount;
        paidToday[s.id] = (paidToday[s.id] ?? 0) + x.amount;
      }
    }
  }
  return ShopsData(shops, ledgers, todaySales, todayPaid, paidToday);
}

class ShopDetail {
  ShopDetail(this.ledger, this.sales, this.pays);
  final ShopLedger ledger;
  final List<SaleLine> sales;
  final List<Payment> pays;
}

Future<ShopDetail> loadShopDetail(String shopId) async {
  final sales = (await Db.i.allSales()).where((s) => s.shopId == shopId).toList();
  final pays = (await Db.i.allPayments()).where((x) => x.shopId == shopId).toList();
  return ShopDetail(buildLedger(sales, pays), sales, pays);
}

// ================================================================ database

class Db extends ChangeNotifier {
  Db._();
  static final Db i = Db._();

  late Database _db;

  static const tables = ['shops', 'items', 'sales', 'payments', 'trader_payments', 'expenses'];

  Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      pth.join(dir, 'distributor.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute(
            'CREATE TABLE shops(id TEXT PRIMARY KEY, name TEXT, phone TEXT, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE items(id TEXT PRIMARY KEY, name TEXT, unit TEXT, sell_price INTEGER, cost_price INTEGER, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE sales(id TEXT PRIMARY KEY, shop_id TEXT, item_id TEXT, date TEXT, qty REAL, sell_price INTEGER, cost_price INTEGER, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE payments(id TEXT PRIMARY KEY, shop_id TEXT, date TEXT, amount INTEGER, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE trader_payments(id TEXT PRIMARY KEY, date TEXT, amount INTEGER, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE expenses(id TEXT PRIMARY KEY, date TEXT, note TEXT, amount INTEGER, is_income INTEGER, updated_at INTEGER, deleted INTEGER DEFAULT 0)');
      },
    );
  }

  Future<void> _upsert(String table, Map<String, Object?> row) async {
    await _db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  /// الحذف دائماً "علامة" وليس مسحاً فعلياً، حتى يعمل الدمج بين النسخ بشكل صحيح
  Future<void> softDelete(String table, String id) async {
    await _db.update(table, {'deleted': 1, 'updated_at': nowMs()}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ---- shops
  Future<List<Shop>> shops() async {
    final r = await _db.query('shops', where: 'deleted = 0', orderBy: 'name');
    return r.map(Shop.fromMap).toList();
  }

  Future<void> saveShop(Shop s) =>
      _upsert('shops', {'id': s.id, 'name': s.name, 'phone': s.phone, 'updated_at': nowMs(), 'deleted': 0});

  Future<void> deleteShop(String id) async {
    final t = nowMs();
    await _db.transaction((txn) async {
      await txn.update('shops', {'deleted': 1, 'updated_at': t}, where: 'id = ?', whereArgs: [id]);
      await txn.update('sales', {'deleted': 1, 'updated_at': t}, where: 'shop_id = ?', whereArgs: [id]);
      await txn.update('payments', {'deleted': 1, 'updated_at': t}, where: 'shop_id = ?', whereArgs: [id]);
    });
    notifyListeners();
  }

  // ---- items
  Future<List<Item>> items() async {
    final r = await _db.query('items', where: 'deleted = 0', orderBy: 'name');
    return r.map(Item.fromMap).toList();
  }

  Future<void> saveItem(Item it) => _upsert('items', {
        'id': it.id,
        'name': it.name,
        'unit': it.unit,
        'sell_price': it.sellPrice,
        'cost_price': it.costPrice,
        'updated_at': nowMs(),
        'deleted': 0,
      });

  // ---- sales
  static const _saleSql =
      'SELECT s.*, i.name AS item_name, i.unit AS unit FROM sales s LEFT JOIN items i ON i.id = s.item_id WHERE s.deleted = 0';

  Future<List<SaleLine>> allSales() async {
    final r = await _db.rawQuery('$_saleSql ORDER BY s.date');
    return r.map(SaleLine.fromMap).toList();
  }

  Future<List<SaleLine>> salesOfShopDate(String shopId, String date) async {
    final r = await _db.rawQuery('$_saleSql AND s.shop_id = ? AND s.date = ?', [shopId, date]);
    return r.map(SaleLine.fromMap).toList();
  }

  Future<void> saveDay(List<SaleLine> upserts, List<String> removeIds) async {
    final t = nowMs();
    await _db.transaction((txn) async {
      for (final l in upserts) {
        await txn.insert('sales', l.toMap(t), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final id in removeIds) {
        await txn.update('sales', {'deleted': 1, 'updated_at': t}, where: 'id = ?', whereArgs: [id]);
      }
    });
    notifyListeners();
  }

  Future<void> deleteDay(String shopId, String date) async {
    await _db.update('sales', {'deleted': 1, 'updated_at': nowMs()},
        where: 'shop_id = ? AND date = ? AND deleted = 0', whereArgs: [shopId, date]);
    notifyListeners();
  }

  // ---- payments (shops)
  Future<List<Payment>> allPayments() async {
    final r = await _db.query('payments', where: 'deleted = 0', orderBy: 'date');
    return r.map(Payment.fromMap).toList();
  }

  Future<void> addPayment(String shopId, String date, int amount) => _upsert('payments',
      {'id': newId(), 'shop_id': shopId, 'date': date, 'amount': amount, 'updated_at': nowMs(), 'deleted': 0});

  // ---- trader payments
  Future<List<TraderPayment>> traderPayments() async {
    final r = await _db.query('trader_payments', where: 'deleted = 0', orderBy: 'date');
    return r.map(TraderPayment.fromMap).toList();
  }

  Future<void> addTraderPayment(String date, int amount) => _upsert('trader_payments',
      {'id': newId(), 'date': date, 'amount': amount, 'updated_at': nowMs(), 'deleted': 0});

  // ---- expenses / manual incomes
  Future<List<Expense>> expenses() async {
    final r = await _db.query('expenses', where: 'deleted = 0', orderBy: 'date');
    return r.map(Expense.fromMap).toList();
  }

  Future<void> addExpense(String date, String note, int amount, bool isIncome) => _upsert('expenses', {
        'id': newId(),
        'date': date,
        'note': note,
        'amount': amount,
        'is_income': isIncome ? 1 : 0,
        'updated_at': nowMs(),
        'deleted': 0,
      });

  // ================================================================ backup

  Future<File> exportBackup() async {
    final data = <String, Object?>{};
    for (final t in tables) {
      data[t] = await _db.query(t);
    }
    final doc = {
      'app': 'distributor',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'tables': data,
    };
    final dir = await getTemporaryDirectory();
    final f = File(pth.join(dir.path, 'distributor-backup-${ymd(DateTime.now())}.json'));
    await f.writeAsString(jsonEncode(doc));
    return f;
  }

  /// merge = true : يضيف السجلات الناقصة، وعند التعارض يبقى الأحدث (حسب updated_at)
  /// merge = false: يمسح كل شيء ويرجّع النسخة كما هي
  Future<String> importBackup(String filePath, {required bool merge}) async {
    final doc = jsonDecode(await File(filePath).readAsString());
    if (doc is! Map || doc['app'] != 'distributor' || doc['tables'] is! Map) {
      throw const FormatException('ملف غير صالح');
    }
    final data = doc['tables'] as Map;
    var added = 0;
    var updated = 0;
    await _db.transaction((txn) async {
      if (!merge) {
        for (final t in tables) {
          await txn.delete(t);
        }
      }
      for (final t in tables) {
        final rows = (data[t] as List?) ?? const [];
        for (final r in rows) {
          final row = Map<String, Object?>.from(r as Map);
          final ex = await txn.query(t,
              columns: ['updated_at'], where: 'id = ?', whereArgs: [row['id']]);
          if (ex.isEmpty) {
            await txn.insert(t, row);
            added++;
          } else if (_i(ex.first['updated_at']) < _i(row['updated_at'])) {
            await txn.update(t, row, where: 'id = ?', whereArgs: [row['id']]);
            updated++;
          }
        }
      }
    });
    notifyListeners();
    return 'تم الاسترداد: أُضيف $added سجل، وحُدّث $updated سجل';
  }
}

// ================================================================ helper widget

/// يحمّل البيانات ويعيد التحميل تلقائياً عند أي تغيير في قاعدة البيانات
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  T? _data;
  bool _has = false;

  @override
  void initState() {
    super.initState();
    Db.i.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant DbBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  @override
  void dispose() {
    Db.i.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final d = await widget.load();
    if (!mounted) return;
    setState(() {
      _data = d;
      _has = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_has) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}
