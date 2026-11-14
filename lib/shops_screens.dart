import 'package:flutter/material.dart';

import 'data.dart';
import 'settings_screens.dart';
import 'util.dart';

// ================================================================ قائمة الدكاكين

class ShopsTab extends StatefulWidget {
  const ShopsTab({super.key});
  @override
  State<ShopsTab> createState() => _ShopsTabState();
}

class _ShopsTabState extends State<ShopsTab> {
  String q = '';

  Future<void> _add() async {
    final name = await askText(context, 'اسم الدكان');
    if (name != null && name.isNotEmpty) {
      await Db.i.saveShop(Shop(id: newId(), name: name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدكاكين')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('دكان جديد'),
      ),
      body: DbBuilder<ShopsData>(
        load: loadShopsData,
        builder: (ctx, d) {
          final today = ymd(DateTime.now());
          final list = d.shops.where((s) => s.name.contains(q)).toList();
          final total = d.totalBalance;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              Row(children: [
                statTile(ctx, 'وُزّع اليوم', fmtMoney(d.todaySales)),
                statTile(ctx, 'حُصّل اليوم', fmtMoney(d.todayPaid), color: kPrimary),
                statTile(ctx, 'المتبقي الكلي', fmtMoney(total),
                    color: total > 0 ? debtColor(ctx) : null),
              ]),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث عن دكان',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('لا توجد دكاكين. اضغط "دكان جديد" للبدء.')),
                ),
              for (final s in list) _card(ctx, s, d.ledgers[s.id]!, today),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext ctx, Shop s, ShopLedger l, String today) {
    final t = l.day(today)?.total;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: t != null ? const Color(0xFFE3F0EC) : null,
          foregroundColor: t != null ? kPrimary : null,
          child: Text(s.name.isEmpty ? '؟' : s.name.substring(0, 1),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: Text(t != null ? 'وُزّع اليوم · ${fmtMoney(t)}' : 'لم يُوزَّع اليوم'),
        trailing: BalanceBadge(l.balance),
        onTap: () => Navigator.push(
            ctx, MaterialPageRoute(builder: (_) => ShopDetailScreen(shop: s))),
      ),
    );
  }
}

// ================================================================ تفاصيل الدكان

class ShopDetailScreen extends StatefulWidget {
  const ShopDetailScreen({super.key, required this.shop});
  final Shop shop;
  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  late Shop shop = widget.shop;
  DateTime date = DateTime.now();
  String get ds => ymd(date);

  DateTime _shift(int days) => DateTime(date.year, date.month, date.day + days);

  Future<void> _rename() async {
    final n = await askText(context, 'اسم الدكان', initial: shop.name);
    if (n != null && n.isNotEmpty) {
      final s = Shop(id: shop.id, name: n, phone: shop.phone);
      await Db.i.saveShop(s);
      setState(() => shop = s);
    }
  }

  Future<void> _deleteShop() async {
    final ok = await confirmDialog(
        context, 'حذف دكان "${shop.name}" مع كل توزيعاته ودفعاته؟');
    if (!ok) return;
    await Db.i.deleteShop(shop.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> _collect() async {
    final d = await loadShopDetail(shop.id);
    if (!mounted) return;
    final amt = await askPayment(context,
        title: 'تحصيل · ${arDate(date)}', due: d.ledger.balance);
    if (amt != null) await Db.i.addPayment(shop.id, ds, amt);
  }

  Future<void> _distribute() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => DistributeScreen(shop: shop, date: ds)));
  }

  Future<void> _deleteDay() async {
    final ok = await confirmDialog(context, 'حذف توزيع ${arDate(date)} كاملاً؟');
    if (ok) await Db.i.deleteDay(shop.id, ds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        actions: [
          IconButton(
              tooltip: 'تعديل الاسم',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _rename),
          IconButton(
              tooltip: 'حذف الدكان',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteShop),
        ],
      ),
      body: DbBuilder<ShopDetail>(
        load: () => loadShopDetail(shop.id),
        builder: _body,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _collect,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تحصيل'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _distribute,
                icon: const Icon(Icons.add),
                label: const Text('توزيع / تعديل'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body(BuildContext ctx, ShopDetail d) {
    final l = d.ledger;
    final today = ymd(DateTime.now());
    final bal = l.balance;
    final prior = bal - (l.day(today)?.remaining ?? 0);
    final day = l.day(ds);
    final lines = d.sales.where((s) => s.date == ds).toList();
    final pays = d.pays.where((p) => p.date == ds).toList();
    final cs = Theme.of(ctx).colorScheme;
    final Color c = bal > 0
        ? debtColor(ctx)
        : bal < 0
            ? creditColor(ctx)
            : cs.onSurface;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي المتبقي على الدكان'),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(fmtMoney(bal.abs()),
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c)),
                    const SizedBox(width: 8),
                    Text(bal > 0 ? 'ريال · عليه' : bal < 0 ? 'ريال · له' : 'مسدّد'),
                  ],
                ),
                if (prior != 0) ...[
                  const SizedBox(height: 4),
                  Text('منها من الأيام السابقة: ${fmtMoney(prior)}'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          IconButton.outlined(
            tooltip: 'اليوم السابق',
            onPressed: () => setState(() => date = _shift(-1)),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(ds == today ? 'اليوم · ${arDate(date)}' : arDate(date)),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'اليوم التالي',
            onPressed: ds == today ? null : () => setState(() => date = _shift(1)),
            icon: const Icon(Icons.chevron_left),
          ),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(children: [
                  const Expanded(
                      child: Text('توزيع اليوم',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  if (lines.isNotEmpty) ...[
                    IconButton(
                        tooltip: 'تعديل التوزيع',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _distribute),
                    IconButton(
                        tooltip: 'حذف التوزيع',
                        icon: Icon(Icons.delete_outline, color: debtColor(ctx)),
                        onPressed: _deleteDay),
                  ],
                ]),
              ),
              if (lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text('لا يوجد توزيع في هذا اليوم'),
                ),
              for (final s in lines)
                ListTile(
                  dense: true,
                  title: Text(s.itemName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  subtitle: Text('${fmtQty(s.qty)} ${s.unit} × ${fmtMoney(s.sellPrice)}'),
                  trailing: Text(fmtMoney(s.total),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              if (lines.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Column(children: [
                    kvRow('إجمالي توزيع هذا اليوم', fmtMoney(day?.total ?? 0)),
                    kvRow('سُدّد من هذا التوزيع', fmtMoney(day?.paid ?? 0)),
                    kvRow('المتبقي من هذا اليوم', fmtMoney(day?.remaining ?? 0),
                        bold: true,
                        color: (day?.remaining ?? 0) > 0 ? debtColor(ctx) : null),
                    if (ds != today)
                      kvRow('الرصيد الإجمالي حتى نهاية هذا اليوم', fmtMoney(l.balanceAt(ds))),
                  ]),
                ),
            ],
          ),
        ),
        if (pays.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              for (final p in pays)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text('دفعة ${fmtMoney(p.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: IconButton(
                    tooltip: 'حذف الدفعة',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirmDialog(ctx, 'حذف هذه الدفعة؟');
                      if (ok) await Db.i.softDelete('payments', p.id);
                    },
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

// ================================================================ شاشة التوزيع

class DistributeScreen extends StatefulWidget {
  const DistributeScreen({super.key, required this.shop, required this.date});
  final Shop shop;
  final String date;
  @override
  State<DistributeScreen> createState() => _DistributeScreenState();
}

class _DistributeScreenState extends State<DistributeScreen> {
  List<Item> items = [];
  final qty = <String, double>{};
  final sell = <String, int>{};
  final cost = <String, int>{};
  final lineIds = <String, String>{};
  final undo = <String, List<double>>{};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    items = await Db.i.items();
    final lines = await Db.i.salesOfShopDate(widget.shop.id, widget.date);
    for (final it in items) {
      qty[it.id] = 0;
      sell[it.id] = it.sellPrice;
      cost[it.id] = it.costPrice;
    }
    for (final l in lines) {
      if (!qty.containsKey(l.itemId)) continue;
      qty[l.itemId] = l.qty;
      sell[l.itemId] = l.sellPrice;
      cost[l.itemId] = l.costPrice;
      lineIds[l.itemId] = l.id;
    }
    if (mounted) setState(() => loading = false);
  }

  double _round(double v) => (v * 100).round() / 100;

  void _add(String id, double step) {
    setState(() {
      qty[id] = _round((qty[id] ?? 0) + step);
      (undo[id] ??= []).add(step);
    });
  }

  void _minus(String id) {
    setState(() {
      final stack = undo[id] ?? [];
      final step = stack.isNotEmpty ? stack.removeLast() : 0.25;
      final v = _round((qty[id] ?? 0) - step);
      qty[id] = v < 0 ? 0 : v;
    });
  }

  Future<void> _typeQty(Item it) async {
    final cur = qty[it.id] ?? 0;
    final v = await askNumber(context, 'الكمية (${it.unit})',
        initial: cur == 0 ? '' : '$cur');
    if (v != null && v >= 0) {
      setState(() {
        qty[it.id] = _round(v);
        undo[it.id] = [];
      });
    }
  }

  Future<void> _editPrice(Item it) async {
    final v = await askAmount(context, 'سعر ${it.name} لهذا التوزيع فقط',
        initial: '${sell[it.id] ?? it.sellPrice}');
    if (v != null && v >= 0) setState(() => sell[it.id] = v);
  }

  int get total {
    var t = 0;
    for (final it in items) {
      t += ((qty[it.id] ?? 0) * (sell[it.id] ?? 0)).round();
    }
    return t;
  }

  Future<void> _save() async {
    final ups = <SaleLine>[];
    final rem = <String>[];
    for (final it in items) {
      final q = qty[it.id] ?? 0;
      if (q > 0) {
        ups.add(SaleLine(
          id: lineIds[it.id] ?? newId(),
          shopId: widget.shop.id,
          itemId: it.id,
          date: widget.date,
          qty: q,
          sellPrice: sell[it.id] ?? it.sellPrice,
          costPrice: cost[it.id] ?? it.costPrice,
        ));
      } else if (lineIds.containsKey(it.id)) {
        rem.add(lineIds[it.id]!);
      }
    }
    await Db.i.saveDay(ups, rem);
    if (mounted) Navigator.pop(context);
  }

  Widget _addBtn(String id, double step, String label) {
    return FilledButton.tonal(
      onPressed: () => _add(id, step),
      style: FilledButton.styleFrom(
        minimumSize: const Size(52, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, textDirection: TextDirection.ltr),
    );
  }

  Widget _itemCard(Item it) {
    final q = qty[it.id] ?? 0;
    final price = sell[it.id] ?? it.sellPrice;
    final line = (q * price).round();
    final active = q > 0;
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active ? cs.primary : cs.outlineVariant, width: active ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(it.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Text(fmtMoney(line),
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: active ? cs.primary : null)),
            ]),
            Row(children: [
              Text('السعر: ${fmtMoney(price)} / ${it.unit}'),
              IconButton(
                tooltip: 'تعديل السعر لهذا التوزيع',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editPrice(it),
              ),
            ]),
            Row(children: [
              IconButton.outlined(
                tooltip: 'تقليل',
                onPressed: q > 0 ? () => _minus(it.id) : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => _typeQty(it),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${fmtQty(q)} ${it.unit}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              _addBtn(it.id, 0.25, '+¼'),
              const SizedBox(width: 4),
              _addBtn(it.id, 0.5, '+½'),
              const SizedBox(width: 4),
              _addBtn(it.id, 1, '+1'),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = parseYmd(widget.date);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('توزيع', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('${widget.shop.name} · ${arDate(d)}', style: const TextStyle(fontSize: 13)),
        ]),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('لا توجد أصناف بعد'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ItemsScreen()));
                        await _load();
                      },
                      child: const Text('إضافة أصناف'),
                    ),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text('اضغط +¼ أو +½ أو +1 لإضافة الكمية. واضغط على الرقم لكتابة كمية يدوياً.',
                          style: TextStyle(fontSize: 13)),
                    ),
                    for (final it in items) _itemCard(it),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(children: [
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مجموع التوزيع', style: TextStyle(fontSize: 13)),
              Text(fmtMoney(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: loading ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('حفظ التوزيع', style: TextStyle(fontSize: 17)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
