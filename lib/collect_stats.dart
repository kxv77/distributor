import 'package:flutter/material.dart';

import 'data.dart';
import 'shops_screens.dart';
import 'util.dart';

// ================================================================ التحصيل

class CollectTab extends StatelessWidget {
  const CollectTab({super.key});

  Future<void> _collect(BuildContext ctx, Shop s, ShopLedger l) async {
    final amt = await askPayment(ctx, title: 'تحصيل من ${s.name}', due: l.balance);
    if (amt != null) await Db.i.addPayment(s.id, ymd(DateTime.now()), amt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحصيل')),
      body: DbBuilder<ShopsData>(
        load: loadShopsData,
        builder: (ctx, d) {
          final today = ymd(DateTime.now());
          final list = d.shops.where((s) {
            final l = d.ledgers[s.id]!;
            return l.balance != 0 || l.day(today) != null;
          }).toList()
            ..sort((a, b) => d.ledgers[b.id]!.balance.compareTo(d.ledgers[a.id]!.balance));
          final remaining = d.totalBalance;
          final base = d.todayPaid + (remaining > 0 ? remaining : 0);
          final progress = base == 0 ? 0.0 : d.todayPaid / base;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('حُصّل اليوم'),
                      Text(fmtMoney(d.todayPaid),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary)),
                    ]),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                        value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 10),
                    kvRow('المتبقي عند الدكاكين', fmtMoney(remaining)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              if (list.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لا يوجد شيء للتحصيل حالياً'))),
              for (final s in list) _shopCard(ctx, s, d, today),
            ],
          );
        },
      ),
    );
  }

  Widget _shopCard(BuildContext ctx, Shop s, ShopsData d, String today) {
    final l = d.ledgers[s.id]!;
    final bal = l.balance;
    final prior = bal - (l.day(today)?.remaining ?? 0);
    final paid = d.paidToday[s.id] ?? 0;
    String sub;
    if (bal > 0) {
      sub = 'المطلوب: ${fmtMoney(bal)}${prior > 0 ? ' (منها سابق ${fmtMoney(prior)})' : ''}';
    } else if (bal < 0) {
      sub = 'له رصيد ${fmtMoney(-bal)}';
    } else {
      sub = 'مسدّد';
    }
    if (paid > 0) sub += '\nحُصّل اليوم: ${fmtMoney(paid)}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: Text(sub),
        trailing: FilledButton.tonal(
          onPressed: () => _collect(ctx, s, l),
          child: const Text('تحصيل'),
        ),
        onTap: () => Navigator.push(
            ctx, MaterialPageRoute(builder: (_) => ShopDetailScreen(shop: s))),
      ),
    );
  }
}

// ================================================================ الإحصائيات

class ItemStat {
  ItemStat(this.name, this.unit);
  final String name, unit;
  double qty = 0;
  int profit = 0;
}

class StatsData {
  int sales = 0, cost = 0, expenses = 0, incomes = 0, collected = 0;
  int remainingShops = 0, traderPurchases = 0, traderPaid = 0, traderRemaining = 0;
  List<MapEntry<String, int>> daily = [];
  List<ItemStat> items = [];
  List<Expense> manual = [];
  int get gross => sales - cost;
  int get net => gross - expenses + incomes;
}

Future<StatsData> loadStats(String from, String to) async {
  final sales = await Db.i.allSales();
  final pays = await Db.i.allPayments();
  final exp = await Db.i.expenses();
  final tp = await Db.i.traderPayments();
  final sd = await loadShopsData();
  final liveShops = sd.shops.map((s) => s.id).toSet();

  bool inR(String d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  final s = StatsData();
  final byDay = <String, int>{};
  final items = <String, ItemStat>{};
  var allCost = 0;

  for (final l in sales) {
    if (!liveShops.contains(l.shopId)) continue;
    allCost += l.cost;
    if (!inR(l.date)) continue;
    s.sales += l.total;
    s.cost += l.cost;
    byDay[l.date] = (byDay[l.date] ?? 0) + l.total;
    final st = items.putIfAbsent(l.itemId, () => ItemStat(l.itemName, l.unit));
    st.qty += l.qty;
    st.profit += l.total - l.cost;
  }
  for (final p in pays) {
    if (inR(p.date)) s.collected += p.amount;
  }
  for (final e in exp) {
    if (!inR(e.date)) continue;
    s.manual.add(e);
    if (e.isIncome) {
      s.incomes += e.amount;
    } else {
      s.expenses += e.amount;
    }
  }
  var allTraderPaid = 0;
  for (final t in tp) {
    allTraderPaid += t.amount;
    if (inR(t.date)) s.traderPaid += t.amount;
  }
  s.traderPurchases = s.cost;
  s.traderRemaining = allCost - allTraderPaid;
  s.remainingShops = sd.totalBalance;

  final start = parseYmd(from);
  final end = parseYmd(to);
  final n = end.difference(start).inDays + 1;
  if (n >= 1 && n <= 31) {
    for (var i = 0; i < n; i++) {
      final d = ymd(DateTime(start.year, start.month, start.day + i));
      s.daily.add(MapEntry(d, byDay[d] ?? 0));
    }
  }
  s.items = items.values.toList()..sort((a, b) => b.profit.compareTo(a.profit));
  return s;
}

enum Period { today, week, month, custom }

class StatsTab extends StatefulWidget {
  const StatsTab({super.key});
  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  Period period = Period.week;
  DateTimeRange? custom;

  DateTime get _from {
    final n = DateTime.now();
    switch (period) {
      case Period.today:
        return DateTime(n.year, n.month, n.day);
      case Period.week:
        return DateTime(n.year, n.month, n.day - 6);
      case Period.month:
        return DateTime(n.year, n.month, 1);
      case Period.custom:
        return custom?.start ?? DateTime(n.year, n.month, n.day - 6);
    }
  }

  DateTime get _to {
    final n = DateTime.now();
    if (period == Period.custom && custom != null) return custom!.end;
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _addManual() async {
    final r = await showDialog<(String, int, bool)>(
        context: context, builder: (_) => const _ManualDialog());
    if (r != null) await Db.i.addExpense(ymd(DateTime.now()), r.$1, r.$2, r.$3);
  }

  Future<void> _addTraderPayment() async {
    final v = await askAmount(context, 'المبلغ المدفوع للتاجر');
    if (v != null && v > 0) await Db.i.addTraderPayment(ymd(DateTime.now()), v);
  }

  @override
  Widget build(BuildContext context) {
    final from = ymd(_from);
    final to = ymd(_to);
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      body: DbBuilder<StatsData>(
        load: () => loadStats(from, to),
        builder: (ctx, s) => _body(ctx, s),
      ),
    );
  }

  Widget _body(BuildContext ctx, StatsData s) {
    final cs = Theme.of(ctx).colorScheme;
    final maxProfit = s.items.isEmpty ? 1 : (s.items.first.profit <= 0 ? 1 : s.items.first.profit);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SegmentedButton<Period>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: Period.today, label: Text('اليوم')),
            ButtonSegment(value: Period.week, label: Text('الأسبوع')),
            ButtonSegment(value: Period.month, label: Text('الشهر')),
            ButtonSegment(value: Period.custom, label: Text('فترة')),
          ],
          selected: {period},
          onSelectionChanged: (v) async {
            final p = v.first;
            if (p == Period.custom) {
              final r = await showDateRangePicker(
                context: ctx,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (r == null) return;
              setState(() {
                custom = r;
                period = p;
              });
            } else {
              setState(() => period = p);
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(child: Text('من ${arDate(_from)} إلى ${arDate(_to)}')),
        ),
        Card(
          color: cs.primary,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: DefaultTextStyle(
              style: TextStyle(color: cs.onPrimary, fontSize: 15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('صافي الربح'),
                Text('${fmtMoney(s.net)} ريال',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const Divider(color: Colors.white38, height: 24),
                _line('إجمالي المبيعات', fmtMoney(s.sales)),
                _line('تكلفة الشراء', '- ${fmtMoney(s.cost)}'),
                _line('الربح الإجمالي', fmtMoney(s.gross)),
                _line('المصاريف اليدوية', '- ${fmtMoney(s.expenses)}'),
                if (s.incomes > 0) _line('إيرادات يدوية', '+ ${fmtMoney(s.incomes)}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addManual,
                  icon: const Icon(Icons.add),
                  label: const Text('مصروف أو إيراد يدوي'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onPrimary,
                    side: BorderSide(color: cs.onPrimary.withOpacity(0.7)),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (s.manual.isNotEmpty)
          Card(
            child: Column(children: [
              for (final e in s.manual)
                ListTile(
                  dense: true,
                  title: Text(e.note.isEmpty ? (e.isIncome ? 'إيراد' : 'مصروف') : e.note),
                  subtitle: Text(arDate(parseYmd(e.date))),
                  leading: Text(e.isIncome ? '+' : '-',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: e.isIncome ? creditColor(ctx) : debtColor(ctx))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtMoney(e.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmDialog(ctx, 'حذف هذا البند؟')) {
                          await Db.i.softDelete('expenses', e.id);
                        }
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        Row(children: [
          statTile(ctx, 'المحصّل فعلياً', fmtMoney(s.collected), color: kPrimary),
          statTile(ctx, 'المتبقي عند الدكاكين', fmtMoney(s.remainingShops),
              color: s.remainingShops > 0 ? debtColor(ctx) : null),
        ]),
        if (s.daily.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('المبيعات يوم بيوم',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _bars(ctx, s.daily),
              ]),
            ),
          ),
        if (s.items.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('تفصيل الأصناف',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final it in s.items) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${fmtQty(it.qty)} ${it.unit} · ربح ${fmtMoney(it.profit)}'),
                  ]),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (it.profit <= 0 ? 0 : it.profit / maxProfit).toDouble(),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('حساب التاجر',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              kvRow('مشتريات الفترة', fmtMoney(s.traderPurchases)),
              kvRow('المدفوع للتاجر في الفترة', fmtMoney(s.traderPaid)),
              const Divider(),
              kvRow(
                s.traderRemaining >= 0 ? 'المتبقي للتاجر (الإجمالي)' : 'التاجر مديون لك بـ',
                fmtMoney(s.traderRemaining.abs()),
                bold: true,
                color: s.traderRemaining > 0 ? debtColor(ctx) : creditColor(ctx),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _addTraderPayment,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: const Text('تسجيل دفعة للتاجر'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(a), Text(b, style: const TextStyle(fontWeight: FontWeight.w800))],
        ),
      );

  Widget _bars(BuildContext ctx, List<MapEntry<String, int>> daily) {
    final maxV = daily.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    final color = Theme.of(ctx).colorScheme.primary;
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in daily)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 110.0 * e.value / maxV,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${parseYmd(e.key).day}', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ManualDialog extends StatefulWidget {
  const _ManualDialog();
  @override
  State<_ManualDialog> createState() => _ManualDialogState();
}

class _ManualDialogState extends State<_ManualDialog> {
  final note = TextEditingController();
  final amount = TextEditingController();
  bool income = false;

  @override
  void dispose() {
    note.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('بند يدوي'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('مصروف')),
            ButtonSegment(value: true, label: Text('إيراد')),
          ],
          selected: {income},
          onSelectionChanged: (v) => setState(() => income = v.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'البيان (بنزين، تالف، عامل...)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المبلغ'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final a = parseInt(amount.text) ?? 0;
            if (a <= 0) return;
            Navigator.pop(context, (note.text.trim(), a, income));
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
