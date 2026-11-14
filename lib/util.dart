import 'package:flutter/material.dart';

const kPrimary = Color(0xFF0E5A4B);

Color debtColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFFFF8A80)
    : const Color(0xFFB3261E);

Color creditColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xFF8AB4F8)
    : const Color(0xFF0B5CAD);

/// 12500 -> 12,500
String fmtMoney(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-${b.toString()}' : b.toString();
}

/// 0.25 -> ¼ ، 1.5 -> 1½ ، 2 -> 2
String fmtQty(double q) {
  final whole = q.floor();
  final frac = q - whole;
  String f = '';
  if ((frac - 0.25).abs() < 0.001) {
    f = '¼';
  } else if ((frac - 0.5).abs() < 0.001) {
    f = '½';
  } else if ((frac - 0.75).abs() < 0.001) {
    f = '¾';
  } else if (frac.abs() > 0.001) {
    var t = q.toStringAsFixed(2);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }
  if (f.isEmpty) return '$whole';
  if (whole == 0) return f;
  return '$whole$f';
}

String two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

String arDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String arDateTime(DateTime d) =>
    '${arDate(d)} ${d.year} - ${two(d.hour)}:${two(d.minute)}';

/// يحوّل الأرقام العربية (٠١٢) إلى إنجليزية ويحذف الفواصل
String normDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b
      .toString()
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll('٫', '.')
      .replaceAll(' ', '');
}

int? parseInt(String s) {
  final n = double.tryParse(normDigits(s));
  return n?.round();
}

double? parseDouble(String s) => double.tryParse(normDigits(s));

// ---------------------------------------------------------------- dialogs

Future<bool> confirmDialog(BuildContext c, String msg, {String ok = 'حذف'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext c, String title, {String initial = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('حفظ')),
      ],
    ),
  );
}

Future<String?> _askNumText(BuildContext c, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('حفظ')),
      ],
    ),
  );
}

Future<int?> askAmount(BuildContext c, String title, {String initial = ''}) async {
  final s = await _askNumText(c, title, initial);
  return s == null ? null : parseInt(s);
}

Future<double?> askNumber(BuildContext c, String title, {String initial = ''}) async {
  final s = await _askNumText(c, title, initial);
  return s == null ? null : parseDouble(s);
}

Future<int?> askPayment(BuildContext c, {required String title, required int due}) {
  return showDialog<int>(
    context: c,
    builder: (ctx) => _PaymentDialog(title: title, due: due),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.title, required this.due});
  final String title;
  final int due;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final ctl = TextEditingController();
  int get amount => parseInt(ctl.text) ?? 0;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final after = widget.due - amount;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المطلوب الآن: ${fmtMoney(widget.due)}'),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'المبلغ المدفوع',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.due > 0)
            Wrap(spacing: 8, children: [
              ActionChip(
                label: const Text('كامل المبلغ'),
                onPressed: () {
                  ctl.text = '${widget.due}';
                  setState(() {});
                },
              ),
            ]),
          const SizedBox(height: 8),
          Text(
            after >= 0
                ? 'المتبقي بعد الدفع: ${fmtMoney(after)}'
                : 'يصبح له رصيد: ${fmtMoney(-after)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('يُسدَّد من توزيع اليوم أولاً ثم من الأقدم',
              style: TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: amount > 0 ? () => Navigator.pop(context, amount) : null,
          child: const Text('تسجيل الدفعة'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- widgets

Widget statTile(BuildContext c, String label, String value, {Color? color}) {
  return Expanded(
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// المبلغ + (عليه / له / مسدّد)
class BalanceBadge extends StatelessWidget {
  const BalanceBadge(this.balance, {super.key});
  final int balance;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (balance > 0) {
      color = debtColor(context);
      label = 'عليه';
    } else if (balance < 0) {
      color = creditColor(context);
      label = 'له';
    } else {
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      label = 'مسدّد';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(fmtMoney(balance.abs()),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

Widget kvRow(String a, String b, {bool bold = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
        Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ],
    ),
  );
}
