import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'app_settings.dart';
import 'data.dart';
import 'util.dart';

// ================================================================ الإعدادات

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  void _msg(BuildContext c, String m) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _backup(BuildContext context) async {
    try {
      final f = await Db.i.exportBackup();
      final r = await Share.shareXFiles(
        [XFile(f.path)],
        text: 'نسخة احتياطية - حسابات الموزع',
      );
      if (r.status != ShareResultStatus.dismissed) AppSettings.i.markBackup();
    } catch (e) {
      if (context.mounted) _msg(context, 'تعذر إنشاء النسخة: $e');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = (r == null || r.files.isEmpty) ? null : r.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرداد نسخة'),
        content: const Text(
            'دمج: يضيف السجلات الناقصة ويحتفظ بالأحدث عند التعارض (موصى به).\n\n'
            'استبدال الكل: يمسح البيانات الحالية ويرجّع النسخة كما هي.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('استبدال الكل')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('دمج')),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;

    if (mode == 'replace') {
      final ok = await confirmDialog(
          context, 'سيتم مسح كل البيانات الحالية. هل أنت متأكد؟',
          ok: 'استبدال');
      if (!ok || !context.mounted) return;
    }
    try {
      final m = await Db.i.importBackup(path, merge: mode == 'merge');
      if (context.mounted) _msg(context, m);
    } catch (e) {
      if (context.mounted) _msg(context, 'الملف غير صالح أو تالف');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: AppSettings.i,
        builder: (ctx, _) {
          final s = AppSettings.i;
          final last = s.lastBackupMs == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(s.lastBackupMs);
          final old = last == null || DateTime.now().difference(last).inDays >= 3;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('المظهر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('تلقائي')),
                  ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
                ],
                selected: {s.mode},
                onSelectionChanged: (v) => s.setMode(v.first),
              ),
              const SizedBox(height: 12),
              const Text('حجم الخط'),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1.0, label: Text('عادي')),
                  ButtonSegment(value: 1.15, label: Text('كبير')),
                  ButtonSegment(value: 1.3, label: Text('كبير جداً')),
                ],
                selected: {s.fontScale},
                onSelectionChanged: (v) => s.setFont(v.first),
              ),
              const Divider(height: 32),
              const Text('البيانات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('الأصناف والأسعار'),
                subtitle: const Text('تغيير السعر لا يؤثر على التوزيعات القديمة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(
                    ctx, MaterialPageRoute(builder: (_) => const ItemsScreen())),
              ),
              const Divider(height: 32),
              const Text('النسخ الاحتياطي',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                last == null
                    ? 'لم تُنشأ نسخة احتياطية بعد'
                    : 'آخر نسخة: ${arDateTime(last)}',
                style: TextStyle(color: old ? debtColor(ctx) : null),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _backup(ctx),
                icon: const Icon(Icons.ios_share),
                label: const Text('إنشاء نسخة احتياطية ومشاركتها'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 6),
              const Text('يُنشأ ملف واحد تحفظه في تلجرام أو واتساب أو أي مكان.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _restore(ctx),
                icon: const Icon(Icons.restore),
                label: const Text('استرداد نسخة'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 6),
              const Text('نزّل الملف من تلجرام ثم اختره هنا. الافتراضي هو الدمج.',
                  style: TextStyle(fontSize: 13)),
            ],
          );
        },
      ),
    );
  }
}

// ================================================================ الأصناف

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  Widget _field(String label, TextEditingController c, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<Item?> _editDialog(BuildContext c, [Item? it]) {
    final name = TextEditingController(text: it?.name ?? '');
    final unit = TextEditingController(text: it?.unit ?? 'كرتون');
    final sell = TextEditingController(text: it == null ? '' : '${it.sellPrice}');
    final cost = TextEditingController(text: it == null ? '' : '${it.costPrice}');
    return showDialog<Item>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(it == null ? 'صنف جديد' : 'تعديل الصنف'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field('اسم الصنف', name),
            _field('الوحدة (كرتون، طبق...)', unit),
            _field('سعر البيع للدكان', sell, number: true),
            _field('سعر الشراء من التاجر', cost, number: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              final u = unit.text.trim();
              Navigator.pop(
                ctx,
                Item(
                  id: it?.id ?? newId(),
                  name: n,
                  unit: u.isEmpty ? 'كرتون' : u,
                  sellPrice: parseInt(sell.text) ?? 0,
                  costPrice: parseInt(cost.text) ?? 0,
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف والأسعار')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final it = await _editDialog(context);
          if (it != null) await Db.i.saveItem(it);
        },
        icon: const Icon(Icons.add),
        label: const Text('صنف جديد'),
      ),
      body: DbBuilder<List<Item>>(
        load: () => Db.i.items(),
        builder: (ctx, items) {
          if (items.isEmpty) {
            return const Center(child: Text('أضف الأصناف (زبادي، جبن، بيض...) وأسعارها'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              for (final it in items)
                Card(
                  child: ListTile(
                    title: Text(it.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    subtitle: Text(
                        'بيع ${fmtMoney(it.sellPrice)} · شراء ${fmtMoney(it.costPrice)} · الوحدة: ${it.unit}'),
                    onTap: () async {
                      final n = await _editDialog(ctx, it);
                      if (n != null) await Db.i.saveItem(n);
                    },
                    trailing: IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDialog(
                            ctx, 'حذف "${it.name}"؟ التوزيعات القديمة تبقى كما هي.');
                        if (ok) await Db.i.softDelete('items', it.id);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
