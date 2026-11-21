// Foot Zone — accueil : liste des tournois, création, sauvegardes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'create_page.dart';
import 'theme.dart';
import 'tournament_page.dart';
import 'widgets.dart';

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _BrandPainter());
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 40;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * k;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(1.5 * k, 1.5 * k, 37 * k, 37 * k), Radius.circular(9 * k)), white);
    final faint = Paint()
      ..color = Colors.white.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k;
    canvas.drawLine(Offset(20 * k, 1.5 * k), Offset(20 * k, 38.5 * k), faint);
    canvas.drawCircle(Offset(20 * k, 20 * k), 7 * k, faint);
    final cone = Paint()
      ..color = const Color(0xFFEC6417)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(8 * k, 28 * k)
      ..lineTo(16 * k, 16 * k)
      ..lineTo(22 * k, 23 * k)
      ..lineTo(31 * k, 12 * k);
    canvas.drawPath(path, cone);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

IconData formatIcon(String f) {
  switch (f) {
    case Fmt.cup:
      return Icons.account_tree_outlined;
    case Fmt.groups:
      return Icons.grid_view_rounded;
    case Fmt.single:
      return Icons.sports_soccer;
    default:
      return Icons.format_list_numbered;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _import(BuildContext context) async {
    final store = StoreScope.read(context);
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      final Uint8List? bytes = await file.readAsBytes();
      if (bytes == null) return;
      final t = store.importJson(utf8.decode(bytes, allowMalformed: true));
      if (!context.mounted) return;
      if (t == null) {
        snack(context, tr('importBad'));
        return;
      }
      snack(context, tr('importOk'));
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TournamentPage(id: t.id)));
    } catch (_) {
      if (context.mounted) snack(context, tr('importBad'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Pal.of(context);
    final list = store.tournaments;
    return Scaffold(
      appBar: FzAppBar(
        toolbarHeight: 72,
        title: Row(children: [
          const BrandMark(size: 40),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('FOOT ZONE', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: .6)),
            Text(tr('tagline'), style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .8), fontWeight: FontWeight.w500)),
          ]),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr('language'),
            icon: const Icon(Icons.translate),
            onSelected: store.setLang,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'fr', child: Text('Français')),
              PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: p.board, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('heroTitle'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1)),
              const SizedBox(height: 10),
              Text(tr('heroText'), style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 15.5, height: 1.4)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatePage())),
                icon: const Icon(Icons.add),
                label: Text(tr('createTournament')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .5), width: 2)),
                onPressed: () => _import(context),
                icon: const Icon(Icons.file_open_outlined),
                label: Text(tr('openBackup')),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          if (store.loadError != null) ...[Banner2(tr('loadError'), icon: Icons.error_outline), const SizedBox(height: 12)],
          if (list.isEmpty)
            EmptyState(
              icon: Icons.emoji_events_outlined,
              text: tr('noTournament'),
              action: OutlinedButton(
                onPressed: () {
                  final t = ExampleTournament.build();
                  store.add(t);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TournamentPage(id: t.id)));
                },
                child: Text(tr('openExample')),
              ),
            )
          else ...[
            SectionTitle(tr('myTournaments')),
            const SizedBox(height: 8),
            for (final t in list) ...[_TournamentCard(t: t), const SizedBox(height: 10)],
          ],
        ],
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  final Tournament t;
  const _TournamentCard({required this.t});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final pr = FZ.progress(t);
    final ch = FZ.champion(t);
    final pct = pr.total == 0 ? 0.0 : pr.done / pr.total;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TournamentPage(id: t.id))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.board, borderRadius: BorderRadius.circular(12)),
              child: Icon(formatIcon(t.format), color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${formatLabel(t.format)}, ${tr('nTeams', {'n': '${t.teams.length}'})}', style: TextStyle(color: p.muted, fontSize: 14)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: p.line, color: p.board2),
                ),
                const SizedBox(height: 6),
                Text(
                  ch != null ? tr('winnerIs', {'name': teamName(t, ch)}) : tr('progress', {'done': '${pr.done}', 'total': '${pr.total}'}),
                  style: TextStyle(color: ch != null ? p.cone : p.muted, fontSize: 13.5, fontWeight: ch != null ? FontWeight.w700 : FontWeight.w500),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (pr.live > 0) const LiveBadge(),
              if (t.example) ...[const SizedBox(height: 6), Chip2(tr('example'))],
            ]),
          ]),
        ),
      ),
    );
  }
}
