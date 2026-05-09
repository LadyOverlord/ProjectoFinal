import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─── PALETA DE CORES ────────────────────────────────────────────────
class _C {
  static const bg        = Color(0xFF0D0D0F);
  static const surface   = Color(0xFF141418);
  static const card      = Color(0xFF1C1C22);
  static const cardHover = Color(0xFF232329);
  static const border    = Color(0xFF2A2A33);
  static const accent    = Color(0xFF4F7EFF);
  static const accentSoft= Color(0x264F7EFF);
  static const green     = Color(0xFF22C55E);
  static const greenSoft = Color(0x2222C55E);
  static const orange    = Color(0xFFF59E0B);
  static const orangeSoft= Color(0x26F59E0B);
  static const red       = Color(0xFFEF4444);
  static const redSoft   = Color(0x26EF4444);
  static const white     = Color(0xFFFFFFFF);
  static const grey1     = Color(0xFFE4E4E7);
  static const grey2     = Color(0xFFA1A1AA);
  static const grey3     = Color(0xFF52525B);
  static const grey4     = Color(0xFF3F3F46);
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with TickerProviderStateMixin {
  String _section = 'dashboard';
  final TextEditingController _searchCtrl = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _go(String s) {
    _fadeCtrl.reset();
    setState(() => _section = s);
    _fadeCtrl.forward();
    if (MediaQuery.of(context).size.width <= 700) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _AppBar(searchCtrl: _searchCtrl),
      drawer: wide ? null : _Drawer(section: _section, onNav: _go),
      body: Row(
        children: [
          if (wide) _SideMenu(section: _section, onNav: _go),
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_section) {
      case 'dashboard': return _DashboardPanel();
      case 'users':     return _UsersPanel(searchCtrl: _searchCtrl);
      case 'reports':   return _ApprovalsPanel();
      case 'config':    return _ConfigPanel();
      default:          return const SizedBox();
    }
  }
}

// ─── APP BAR ────────────────────────────────────────────────────────
class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController searchCtrl;
  const _AppBar({required this.searchCtrl});

  @override
  Size get preferredSize => const Size.fromHeight(110);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Builder(builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu_rounded, color: _C.grey1, size: 24),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  )),
                  const SizedBox(width: 8),
                  const Text('Painel de Controle',
                    style: TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  const Spacer(),
                  _NotifBadge(),
                  const SizedBox(width: 12),
                  _AdminAvatar(),
                ],
              ),
              const SizedBox(height: 10),
              _SearchBar(ctrl: searchCtrl),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('casos_pendentes')
          .snapshots(),
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.border)),
              child: const Icon(Icons.notifications_rounded, color: _C.grey2, size: 20),
            ),
            if (count > 0)
              Positioned(
                top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: _C.red, shape: BoxShape.circle),
                  child: Text('$count', style: const TextStyle(color: _C.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdminAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final letter = (user?.email ?? 'A')[0].toUpperCase();
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4F7EFF), Color(0xFF9B5DE5)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Text(letter, style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold, fontSize: 16))),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  const _SearchBar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border)),
      child: Row(
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.search_rounded, color: _C.grey3, size: 18)),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: _C.grey1, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Procurar usuários, casos...',
                hintStyle: TextStyle(color: _C.grey3, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SIDE MENU (tablet/desktop) ──────────────────────────────────────
class _SideMenu extends StatelessWidget {
  final String section;
  final void Function(String) onNav;
  const _SideMenu({required this.section, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(right: BorderSide(color: _C.border, width: 1)),
      ),
      child: _MenuContent(section: section, onNav: onNav),
    );
  }
}

class _Drawer extends StatelessWidget {
  final String section;
  final void Function(String) onNav;
  const _Drawer({required this.section, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _C.surface,
      child: _MenuContent(section: section, onNav: onNav),
    );
  }
}

class _MenuContent extends StatelessWidget {
  final String section;
  final void Function(String) onNav;
  const _MenuContent({required this.section, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 40),
        // Logo
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A2444), Color(0xFF0D0D0F)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.accentSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_C.accent, Color(0xFF9B5DE5)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_searching_rounded, color: _C.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MissingAO', style: TextStyle(color: _C.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.3)),
                  Text('Admin Panel', style: TextStyle(color: _C.grey3, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _label('NAVEGAÇÃO'),
        _item('dashboard', Icons.grid_view_rounded,    'Dashboard',    section, onNav),
        _item('users',     Icons.people_alt_rounded,   'Utilizadores', section, onNav),
        _item('reports',   Icons.fact_check_rounded,   'Aprovações',   section, onNav),
        _item('config',    Icons.tune_rounded,          'Configurações',section, onNav),
        const Spacer(),
        Divider(color: _C.border, height: 1),
        _LogoutTile(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 24, bottom: 6, top: 4),
    child: Text(t, style: const TextStyle(color: _C.grey3, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
  );

  Widget _item(String id, IconData icon, String label, String active, void Function(String) nav) {
    final isActive = active == id;
    return GestureDetector(
      onTap: () => nav(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? _C.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive ? Border.all(color: _C.accent.withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? _C.accent : _C.grey2),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              color: isActive ? _C.accent : _C.grey2,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            )),
            if (isActive) ...[
              const Spacer(),
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(color: _C.accent, shape: BoxShape.circle)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async => await FirebaseAuth.instance.signOut(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _C.redSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.red.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, size: 18, color: _C.red),
            SizedBox(width: 12),
            Text('Sair', style: TextStyle(color: _C.red, fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─── DASHBOARD ──────────────────────────────────────────────────────
class _DashboardPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionTitle('Visão Geral', subtitle: 'Resumo em tempo real da plataforma'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _StatCard(
              label: 'Total Usuários', collection: 'users',
              icon: Icons.people_alt_rounded, color: _C.accent, colorSoft: _C.accentSoft,
            )),
            const SizedBox(width: 14),
            Expanded(child: _StatCard(
              label: 'Casos Pendentes',
              collection: 'casos_pendentes',
              icon: Icons.hourglass_top_rounded, color: _C.orange, colorSoft: _C.orangeSoft,
            )),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _StatCard(
              label: 'Casos Ativos',
              collection: 'casos', whereField: 'status', whereValue: 'aprovado',
              icon: Icons.search_rounded, color: _C.green, colorSoft: _C.greenSoft,
            )),
            const SizedBox(width: 14),
            Expanded(child: _StatCard(
              label: 'Encontrados',
              collection: 'casos', whereField: 'status', whereValue: 'encontrado',
              icon: Icons.check_circle_rounded, color: const Color(0xFF9B5DE5), colorSoft: const Color(0x269B5DE5),
            )),
          ],
        ),
        const SizedBox(height: 32),
        _SectionTitle('Gerir Casos Ativos', subtitle: 'Altere o status de casos aprovados'),
        const SizedBox(height: 16),
        _ActiveCasesTable(),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionTitle(this.title, {this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: _C.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: const TextStyle(color: _C.grey3, fontSize: 13)),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, collection;
  final String? whereField, whereValue;
  final IconData icon;
  final Color color, colorSoft;
  const _StatCard({
    required this.label, required this.collection,
    this.whereField, this.whereValue,
    required this.icon, required this.color, required this.colorSoft,
  });

  Stream<QuerySnapshot> get _stream {
    final col = FirebaseFirestore.instance.collection(collection);
    if (whereField != null) return col.where(whereField!, isEqualTo: whereValue).snapshots();
    return col.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: colorSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 16),
              Text('$count',
                style: TextStyle(color: color, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: _C.grey2, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveCasesTable extends StatefulWidget {
  @override
  State<_ActiveCasesTable> createState() => _ActiveCasesTableState();
}

class _ActiveCasesTableState extends State<_ActiveCasesTable> {
  final Map<String, String> _pendingStatus = {};
  final Set<String> _saving = {};

  Future<void> _save(String id) async {
    final ns = _pendingStatus[id];
    if (ns == null) return;
    setState(() => _saving.add(id));
    await FirebaseFirestore.instance.collection('casos').doc(id).update({'status': ns});
    setState(() { _saving.remove(id); _pendingStatus.remove(id); });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Status atualizado para: $ns'),
        backgroundColor: _C.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('casos')
          .where('status', whereIn: ['aprovado', 'encontrado', 'desmentido']).snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _loading();
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _empty('Nenhum caso ativo.');
        return Column(
          children: docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final current = _pendingStatus[doc.id] ?? d['status'] as String? ?? 'aprovado';
            final saving = _saving.contains(doc.id);
            final changed = _pendingStatus.containsKey(doc.id);
            return _CaseRow(
              name: d['nome'] ?? 'Desconhecido',
              location: d['municipio'] ?? d['provincia'] ?? '—',
              currentStatus: current,
              saving: saving,
              changed: changed,
              onStatusChanged: (v) => setState(() => _pendingStatus[doc.id] = v),
              onSave: () => _save(doc.id),
            );
          }).toList(),
        );
      },
    );
  }
}

class _CaseRow extends StatelessWidget {
  final String name, location, currentStatus;
  final bool saving, changed;
  final void Function(String) onStatusChanged;
  final VoidCallback onSave;
  const _CaseRow({
    required this.name, required this.location, required this.currentStatus,
    required this.saving, required this.changed,
    required this.onStatusChanged, required this.onSave,
  });

  Color get _statusColor {
    switch (currentStatus) {
      case 'aprovado': return _C.accent;
      case 'encontrado': return _C.green;
      case 'desmentido': return _C.grey3;
      case 'rejeitado': return _C.red;
      default: return _C.grey2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: changed ? _C.accent.withOpacity(0.4) : _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: _C.grey3),
                      const SizedBox(width: 3),
                      Text(location, style: const TextStyle(color: _C.grey3, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor.withOpacity(0.4)),
                ),
                child: Text(currentStatus.toUpperCase(),
                  style: TextStyle(color: _statusColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentStatus,
                      dropdownColor: _C.cardHover,
                      style: const TextStyle(color: _C.grey1, fontSize: 13),
                      isExpanded: true,
                      onChanged: (v) { if (v != null) onStatusChanged(v); },
                      items: const [
                        DropdownMenuItem(value: 'aprovado',   child: Text('🔵 Ativo (Procurando)')),
                        DropdownMenuItem(value: 'encontrado', child: Text('🟢 Encontrado')),
                        DropdownMenuItem(value: 'desmentido', child: Text('⚫ Desmentido')),
                        DropdownMenuItem(value: 'rejeitado',  child: Text('🔴 Arquivar/Remover')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: changed && !saving ? onSave : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: changed ? _C.accent : _C.grey4,
                    foregroundColor: _C.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _C.white))
                      : const Text('Salvar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── USERS PANEL ─────────────────────────────────────────────────────
class _UsersPanel extends StatefulWidget {
  final TextEditingController searchCtrl;
  const _UsersPanel({required this.searchCtrl});
  @override
  State<_UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<_UsersPanel> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.searchCtrl.addListener(() => setState(() => _query = widget.searchCtrl.text.toLowerCase()));
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Remover Usuário',
        message: 'Esta ação não pode ser desfeita. Deseja continuar?',
        confirmLabel: 'Remover',
        confirmColor: _C.red,
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('users').doc(id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Usuário removido'), backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Gestão de Usuários', subtitle: 'Gerencie todos os utilizadores registados'),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) return _loading();
                var docs = snap.data!.docs;
                if (_query.isNotEmpty) {
                  docs = docs.where((d) {
                    final u = d.data() as Map<String, dynamic>;
                    return (u['nome'] ?? '').toString().toLowerCase().contains(_query)
                        || (u['email'] ?? '').toString().toLowerCase().contains(_query);
                  }).toList();
                }
                if (docs.isEmpty) return _empty('Nenhum utilizador encontrado.');
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = docs[i].data() as Map<String, dynamic>;
                    final id = docs[i].id;
                    return _UserCard(userData: u, docId: id, onDelete: () => _delete(id));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String docId;
  final VoidCallback onDelete;
  const _UserCard({required this.userData, required this.docId, required this.onDelete});

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Desconhecido';
    DateTime dt;
    if (raw is Timestamp) dt = raw.toDate();
    else { dt = DateTime.tryParse(raw.toString()) ?? DateTime.now(); }
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final email = userData['email'] ?? '';
    final nome = userData['nome'] ?? email;
    final role = (userData['role'] ?? 'user') as String;
    final isAdmin = role == 'admin';
    final date = _formatDate(userData['ultimoLogin'] ?? userData['criadoEm']);
    final isActive = userData['ultimoLogin'] != null;
    final letter = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isAdmin
                    ? [const Color(0xFF4F7EFF), const Color(0xFF9B5DE5)]
                    : [_C.grey4, _C.grey3],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(letter,
              style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold, fontSize: 18))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(nome,
                      style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAdmin ? _C.accentSoft : _C.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(role.toUpperCase(),
                        style: TextStyle(
                          color: isAdmin ? _C.accent : _C.grey2,
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(email, style: const TextStyle(color: _C.grey3, fontSize: 12), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      isActive ? Icons.circle : Icons.radio_button_unchecked,
                      size: 8, color: isActive ? _C.green : _C.grey3,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isActive ? 'Ativo · $date' : 'Novo · $date',
                      style: TextStyle(color: isActive ? _C.green : _C.grey3, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: _C.redSoft, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.red.withOpacity(0.2))),
              child: const Icon(Icons.delete_outline_rounded, color: _C.red, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── APPROVALS PANEL ─────────────────────────────────────────────────
class _ApprovalsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('casos_pendentes')
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _loading();
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: _C.greenSoft, shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: _C.green, size: 40),
              ),
              const SizedBox(height: 16),
              const Text('Tudo em dia!', style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Nenhuma aprovação pendente.', style: TextStyle(color: _C.grey3)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _SectionTitle('Aprovações Pendentes', subtitle: '${docs.length} caso(s) aguardando revisão'),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ApprovalCard(doc: docs[i - 1]),
            );
          },
        );
      },
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  final DocumentSnapshot doc;
  const _ApprovalCard({required this.doc});
  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  bool _expanded = false;
  bool _approving = false, _rejecting = false;

  Map<String, dynamic> get d => widget.doc.data() as Map<String, dynamic>;

  Uint8List? get _imageBytes {
    final img = d['imagem'] as String?;
    if (img == null) return null;
    if (img.startsWith('data:image')) {
      return base64Decode(img.split(',').last);
    }
    return null;
  }

  String _daysAgo() {
    final str = d['data_desaparecimento'] as String?;
    if (str == null) return '';
    final dt = DateTime.tryParse(str);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt).inDays;
    return diff == 0 ? 'hoje' : 'há $diff dias';
  }

  Future<void> _aprovar() async {
    setState(() => _approving = true);
    try {
      final data = Map<String, dynamic>.from(d);
      data['status'] = 'aprovado';
      data['aprovadoEm'] = Timestamp.now();
      // Copia para 'casos' e deleta de 'casos_pendentes'
      await FirebaseFirestore.instance.collection('casos').add(data);
      await FirebaseFirestore.instance.collection('casos_pendentes').doc(widget.doc.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Caso aprovado e publicado!'),
          backgroundColor: _C.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      setState(() => _approving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'), backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _rejeitar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Rejeitar Caso',
        message: 'O caso será marcado como rejeitado e não aparecerá no mapa.',
        confirmLabel: 'Rejeitar',
        confirmColor: _C.red,
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _rejecting = true);
    try {
      // Deleta de 'casos_pendentes'
      await FirebaseFirestore.instance.collection('casos_pendentes').doc(widget.doc.id).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Caso rejeitado e removido.'),
        backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      setState(() => _rejecting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'), backgroundColor: _C.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final imgBytes = _imageBytes;
    final dias = _daysAgo();
    final prov = d['provincia'] ?? d['municipio'] ?? 'Local desconhecido';

    return Container(
      decoration: BoxDecoration(
        color: _C.card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image header
          if (imgBytes != null)
            Stack(
              children: [
                Image.memory(imgBytes, height: 200, width: double.infinity, fit: BoxFit.cover),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, _C.card],
                    ),
                  ),
                ),
                // Reject button top right
                Positioned(
                  top: 12, right: 12,
                  child: _RoundIconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: _C.red, bg: _C.redSoft,
                    onTap: _rejecting ? null : _rejeitar,
                    loading: _rejecting,
                  ),
                ),
              ],
            ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imgBytes == null)
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(color: _C.accentSoft, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.person_rounded, color: _C.accent, size: 28),
                      ),
                    if (imgBytes == null) const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['nome'] ?? 'Nome Desconhecido',
                            style: const TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                          const SizedBox(height: 4),
                          Row(children: [
                            _Chip('${d['idade'] ?? '?'} anos', _C.grey3, _C.border),
                            const SizedBox(width: 6),
                            _Chip(d['sexo'] ?? '—', _C.grey3, _C.border),
                          ]),
                        ],
                      ),
                    ),
                    if (imgBytes == null)
                      _RoundIconBtn(
                        icon: Icons.delete_outline_rounded,
                        color: _C.red, bg: _C.redSoft,
                        onTap: _rejecting ? null : _rejeitar,
                        loading: _rejecting,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.location_on_rounded, size: 14, color: _C.grey3),
                  const SizedBox(width: 4),
                  Text('$prov${dias.isNotEmpty ? " · $dias" : ""}',
                    style: const TextStyle(color: _C.grey3, fontSize: 13)),
                ]),
                const SizedBox(height: 12),

                // Expandable details
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _C.surface, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: _C.grey2),
                        const SizedBox(width: 8),
                        const Text('Ver detalhes completos', style: TextStyle(color: _C.grey2, fontSize: 13)),
                        const Spacer(),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: _C.grey3, size: 18),
                      ],
                    ),
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow('BI', d['bi'] ?? 'N/A'),
                        _DetailRow('Roupas', d['roupas'] ?? 'N/A'),
                        _DetailRow('Data', d['data_desaparecimento'] ?? 'N/A'),
                        const Divider(color: _C.border, height: 16),
                        Text(d['informacoes_adicionais'] ?? 'Sem informações adicionais.',
                          style: const TextStyle(color: _C.grey2, fontSize: 13, height: 1.5)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        label: 'Rejeitar',
                        icon: Icons.close_rounded,
                        color: _C.red, bg: _C.redSoft,
                        border: _C.red.withOpacity(0.3),
                        loading: _rejecting,
                        onTap: _rejeitar,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _ActionBtn(
                        label: 'Aprovar Publicação',
                        icon: Icons.check_rounded,
                        color: _C.white, bg: _C.accent,
                        border: _C.accent,
                        loading: _approving,
                        onTap: _aprovar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text('$label:', style: const TextStyle(color: _C.grey3, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(color: _C.grey1, fontSize: 12))),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color textColor, borderColor;
  const _Chip(this.text, this.textColor, this.borderColor);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final VoidCallback? onTap;
  final bool loading;
  const _RoundIconBtn({required this.icon, required this.color, required this.bg, this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3))),
        child: loading
            ? Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)))
            : Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color, bg, border;
  final bool loading;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color,
    required this.bg, required this.border, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border.withOpacity(0.4)),
        ),
        child: loading
            ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }
}

// ─── CONFIG PANEL ────────────────────────────────────────────────────
class _ConfigPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Configurações', subtitle: 'Opções do sistema'),
          const SizedBox(height: 30),
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: _C.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.construction_rounded, color: _C.accent, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Em Construção', style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Esta secção estará disponível em breve.', style: TextStyle(color: _C.grey3, fontSize: 14)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── CONFIRM DIALOG ──────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;
  const _ConfirmDialog({required this.title, required this.message, required this.confirmLabel, required this.confirmColor});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _C.border)),
      title: Text(title, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(color: _C.grey2, fontSize: 14, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: _C.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─── HELPERS ─────────────────────────────────────────────────────────
Widget _loading() => const Center(child: CircularProgressIndicator(color: _C.accent));
Widget _empty(String msg) => Center(child: Text(msg, style: const TextStyle(color: _C.grey3, fontSize: 16)));