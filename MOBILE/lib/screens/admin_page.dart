// screens/admin_page.dart
// ✅ Dashboard com stats em tempo real + tabela de casos ativos com FILTRO
// ✅ Filtros avançados de utilizadores (role, província, data, ordenação)
// ✅ Painel de aprovações com mini-perfil do relator
// ✅ Editar localização de casos no mapa (Google Maps)
// ✅ Mapa de casos admin com legenda e lista de resumo (SEM barra de pesquisa)
// ✅ Promover/rebaixar utilizadores para admin
// ✅ Botão "Voltar ao App" — navega correctamente para HomePage

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/notification_service.dart';
import 'admin_trust_panels.dart';        // ← Trust Score panels
import '../services/trust_service.dart'; // ← Trust Score service
import '../models/user_mode.dart';
import 'home_page.dart'; // ← import da HomePage

// PALETA DE CORES
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
  static const purple    = Color(0xFF9B5DE5);
  static const purpleSoft= Color(0x269B5DE5);
  static const white     = Color(0xFFFFFFFF);
  static const grey1     = Color(0xFFE4E4E7);
  static const grey2     = Color(0xFFA1A1AA);
  static const grey3     = Color(0xFF52525B);
  static const grey4     = Color(0xFF3F3F46);
}

// COORDENADAS DAS PROVÍNCIAS DE ANGOLA
const Map<String, LatLng> provCoords = {
  'luanda':         LatLng(-8.8368,  13.2343),
  'benguela':       LatLng(-12.5763, 13.4055),
  'huambo':         LatLng(-12.776,  15.7388),
  'bié':            LatLng(-12.3764, 17.0557),
  'cabinda':        LatLng(-5.55,    12.2),
  'cuando cubango': LatLng(-16.93,   19.8),
  'cuanza norte':   LatLng(-9.2,     14.7),
  'cuanza sul':     LatLng(-10.9,    14.3),
  'cunene':         LatLng(-16.9,    15.8),
  'huíla':          LatLng(-14.92,   13.5),
  'lunda norte':    LatLng(-8.65,    20.4),
  'lunda sul':      LatLng(-10.0,    21.0),
  'malanje':        LatLng(-9.54,    16.34),
  'moxico':         LatLng(-11.86,   19.92),
  'namibe':         LatLng(-15.1961, 12.1522),
  'uíge':           LatLng(-7.61,    15.06),
  'zaire':          LatLng(-6.1,     12.85),
};

// ─── NAVEGAÇÃO PARA HOME ─────────────────────────────────────────────────────
// Função utilitária usada tanto no menu lateral como no drawer.
// Remove todos os ecrãs anteriores do stack e coloca a HomePage.
void _irParaHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const HomePage(mode: UserMode.authenticated),
    ),
    (route) => false, // remove TUDO do stack — o utilizador não pode voltar ao admin com o botão de volta
  );
}
// ─────────────────────────────────────────────────────────────────────────────

// MAIN WIDGET
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
    _searchCtrl.clear();
    setState(() => _section = s);
    _fadeCtrl.forward();
    if (MediaQuery.of(context).size.width <= 700) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _AppBar(searchCtrl: _searchCtrl, section: _section),
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
      case 'dashboard': return _DashboardPanel(searchCtrl: _searchCtrl);
      case 'users':     return _UsersPanel(searchCtrl: _searchCtrl);
      case 'reports':   return _ApprovalsPanel();
      case 'mapa':        return _MapaAdminPanel();
      case 'comentarios': return const AdminComentariosPanel();  // ← Trust Score
      case 'trust':       return AdminTrustPanel(searchCtrl: _searchCtrl); // ← CORRIGIDO: searchCtrl não estava a ser passado, pesquisa não tinha efeito
      case 'suporte':     return const AdminSuportePanel();      // ← Trust Score
      default:            return const SizedBox();
    }
  }
}

// APP BAR
class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController searchCtrl;
  final String section;
  const _AppBar({required this.searchCtrl, required this.section});

  bool get _showSearch => section != 'mapa';

  @override
  Size get preferredSize => Size.fromHeight(_showSearch ? 126 : 72);

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
                  // ── Botão rápido "Ir para App" na AppBar ──────────────────
                  GestureDetector(
                    onTap: () => _irParaHome(context),
                    child: Container(
                      width: 38, height: 38,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _C.greenSoft,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: _C.green.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.home_rounded, color: _C.green, size: 18),
                    ),
                  ),
                  // ─────────────────────────────────────────────────────────
                  _NotifBadge(),
                  const SizedBox(width: 10),
                  _AdminAvatar(),
                ],
              ),
              if (_showSearch) ...[
                const SizedBox(height: 10),
                _SearchBar(ctrl: searchCtrl),
              ],
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
      stream: FirebaseFirestore.instance.collection('casos_pendentes').snapshots(),
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
                hintText: 'Procurar utilizadores, casos...',
                hintStyle: TextStyle(color: _C.grey3, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: ctrl,
            builder: (_, v, __) => v.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: _C.grey3, size: 16),
                  onPressed: () => ctrl.clear(),
                )
              : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// SIDE MENU
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

        // Itens de navegação
        _label('NAVEGAÇÃO'),
        _item('dashboard', Icons.grid_view_rounded,  'Dashboard',     section, onNav),
        _item('users',     Icons.people_alt_rounded, 'Utilizadores',  section, onNav),
        _item('reports',   Icons.fact_check_rounded, 'Aprovações',    section, onNav),
        _item('mapa',      Icons.map_rounded,        'Mapa de Casos', section, onNav),
        _item('comentarios', Icons.mode_comment_rounded,  'Comentários',   section, onNav),
        _item('trust',       Icons.shield_rounded,        'Trust Scores',  section, onNav),
        _item('suporte',     Icons.support_agent_rounded, 'Suporte',       section, onNav),

        const SizedBox(height: 10),

        // ── SECÇÃO APLICAÇÃO ─────────────────────────────
        _label('APLICAÇÃO'),
        _homeBtn(context),
        // ─────────────────────────────────────────────────

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

  // ── BOTÃO VOLTAR AO APP ───────────────────────────────
  Widget _homeBtn(BuildContext context) {
    return GestureDetector(
      // ✅ FIX: usa _irParaHome em vez de Navigator.pop
      // Navigator.pop só funciona se a AdminPage foi aberta com push.
      // Se veio do AuthCheck (início da app), pop não faz nada.
      // pushAndRemoveUntil navega SEMPRE para a HomePage, em qualquer cenário.
      onTap: () => _irParaHome(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _C.greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.green.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.home_rounded, size: 18, color: _C.green),
            SizedBox(width: 12),
            Text(
              'Voltar ao App',
              style: TextStyle(color: _C.green, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  // NOVO: remove o token FCM desta conta antes de sair — evita que a
  // próxima conta a entrar neste aparelho fique a partilhar o mesmo
  // token e esta conta continue a receber notificações depois de sair.
  Future<void> _sair() async {
    await NotificationService.instance.removerTokenAntesDeSair();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _sair,
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

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardPanel extends StatefulWidget {
  final TextEditingController searchCtrl;
  const _DashboardPanel({required this.searchCtrl});
  @override
  State<_DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<_DashboardPanel> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onSearch);
    super.dispose();
  }

  void _onSearch() => setState(() => _query = widget.searchCtrl.text.toLowerCase());

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
              label: 'Total Utilizadores', collection: 'users',
              icon: Icons.people_alt_rounded, color: _C.accent, colorSoft: _C.accentSoft,
            )),
            const SizedBox(width: 14),
            Expanded(child: _StatCard(
              label: 'Casos Pendentes', collection: 'casos_pendentes',
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
              icon: Icons.check_circle_rounded, color: _C.purple, colorSoft: _C.purpleSoft,
            )),
          ],
        ),
        const SizedBox(height: 32),
        _SectionTitle('Gerir Casos Ativos', subtitle: 'Altere o status de casos aprovados'),
        const SizedBox(height: 16),
        _ActiveCasesTable(query: _query),
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
    if (whereField != null) {
      return col.where(whereField!, isEqualTo: whereValue).snapshots();
    }
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
              Text('$count', style: TextStyle(color: color, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: _C.grey2, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABELA DE CASOS ATIVOS
// ─────────────────────────────────────────────────────────────────────────────
class _ActiveCasesTable extends StatefulWidget {
  final String query;
  const _ActiveCasesTable({required this.query});
  @override
  State<_ActiveCasesTable> createState() => _ActiveCasesTableState();
}

class _ActiveCasesTableState extends State<_ActiveCasesTable> {
  final Map<String, String> _pendingStatus = {};
  final Set<String> _saving = {};

  Future<void> _save(String id) async {
    final ns = _pendingStatus[id];
    if (ns == null) return;

    // NOVO: "Arquivar/Remover" pode significar coisas muito diferentes —
    // desde fraude descoberta depois de aprovado, até um duplicado ou um
    // pedido de remoção legítimo da família, sem culpa do autor. Ao
    // contrário de "Desmentido" (que já implica falsidade comprovada e
    // mantém penalização fixa), aqui o admin decide caso a caso, com o
    // mesmo padrão já usado ao apagar comentários (_ConfirmarApagamento).
    int? pontosArquivamento;
    if (ns == 'rejeitado') {
      pontosArquivamento = await showDialog<int>(
        context: context,
        builder: (_) => const _ConfirmarArquivamento(),
      );
      if (pontosArquivamento == null || !mounted) return; // admin cancelou
    }

    setState(() => _saving.add(id));
    await FirebaseFirestore.instance.collection('casos').doc(id).update({'status': ns});

    // ── Penalizar o autor se o caso foi desmentido ────────────────
    if (ns == 'desmentido') {
      try {
        final casoSnap = await FirebaseFirestore.instance.collection('casos').doc(id).get();
        final autorIdDesm = casoSnap.data()?['userId'] as String? ?? '';
        if (autorIdDesm.isNotEmpty) {
          await TrustService.instance.penalizar(
            uid:      autorIdDesm,
            motivo:   'caso_desmentido',
            pontos:   TrustService.pCasoDesmentido,
            adminUid: FirebaseAuth.instance.currentUser?.uid,
            detalhe:  'Caso removido pelo administrador (desmentido)',
          );
        }
      } catch (e) { debugPrint('Erro penalizar desmentido: \$e'); }
    } else if (ns == 'rejeitado' && (pontosArquivamento ?? 0) > 0) {
      // NOVO: aplica a penalização que o admin escolheu no diálogo acima —
      // 0 é uma opção explícita e válida (caso arquivado sem culpa do autor).
      try {
        final casoSnap = await FirebaseFirestore.instance.collection('casos').doc(id).get();
        final autorIdRej = casoSnap.data()?['userId'] as String? ?? '';
        if (autorIdRej.isNotEmpty) {
          await TrustService.instance.penalizar(
            uid:      autorIdRej,
            motivo:   'caso_rejeitado',
            pontos:   pontosArquivamento!,
            adminUid: FirebaseAuth.instance.currentUser?.uid,
            detalhe:  'Caso arquivado/removido pelo administrador (já aprovado anteriormente)',
          );
        }
      } catch (e) { debugPrint('Erro penalizar arquivamento: \$e'); }
    }
    // ─────────────────────────────────────────────────────────────

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
        if (snap.connectionState == ConnectionState.waiting) return _loadingWidget();
        final allDocs = snap.data?.docs ?? [];

        final docs = widget.query.isEmpty
            ? allDocs
            : allDocs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final nome      = (d['nome']         ?? '').toString().toLowerCase();
                final municipio = (d['municipio']    ?? '').toString().toLowerCase();
                final provincia = (d['provincia']    ?? '').toString().toLowerCase();
                final local     = (d['ultimo_local'] ?? '').toString().toLowerCase();
                return nome.contains(widget.query)
                    || municipio.contains(widget.query)
                    || provincia.contains(widget.query)
                    || local.contains(widget.query);
              }).toList();

        if (allDocs.isEmpty) return _empty('Nenhum caso ativo.');

        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: _empty('Nenhum resultado para "${widget.query}".'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${docs.length} caso${docs.length != 1 ? 's' : ''} encontrado${docs.length != 1 ? 's' : ''}',
                  style: const TextStyle(color: _C.grey2, fontSize: 12),
                ),
              ),
            ...docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final current = _pendingStatus[doc.id] ?? d['status'] as String? ?? 'aprovado';
              final saving  = _saving.contains(doc.id);
              final changed = _pendingStatus.containsKey(doc.id);
              return _CaseRow(
                name: d['nome'] ?? 'Desconhecido',
                location: d['municipio'] ?? d['provincia'] ?? '—',
                currentStatus: current,
                saving: saving,
                changed: changed,
                caseData: d,
                docId: doc.id,
                onStatusChanged: (v) => setState(() => _pendingStatus[doc.id] = v),
                onSave: () => _save(doc.id),
              );
            }),
          ],
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
  // NOVO: dados completos do caso e o id do documento — necessários para
  // mostrar detalhes do caso e do autor, que antes não existiam nesta tabela.
  final Map<String, dynamic> caseData;
  final String docId;
  const _CaseRow({
    required this.name, required this.location, required this.currentStatus,
    required this.saving, required this.changed,
    required this.onStatusChanged, required this.onSave,
    required this.caseData, required this.docId,
  });

  Color get _statusColor {
    switch (currentStatus) {
      case 'aprovado':   return _C.accent;
      case 'encontrado': return _C.green;
      case 'desmentido': return _C.grey3;
      case 'rejeitado':  return _C.red;
      default:           return _C.grey2;
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
              // NOVO: antes não havia nenhuma forma de ver quem publicou o
              // caso, nem os detalhes completos, a partir desta tabela.
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => _CaseDetalhesDialog(caseData: caseData, docId: docId),
                ),
                child: Container(
                  width: 34, height: 34,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _C.purpleSoft, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.purple.withOpacity(0.3))),
                  child: const Icon(Icons.visibility_rounded, color: _C.purple, size: 16),
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
                        DropdownMenuItem(value: 'aprovado',   child: Text('Ativo (Procurando)')),
                        DropdownMenuItem(value: 'encontrado', child: Text('Encontrado')),
                        DropdownMenuItem(value: 'desmentido', child: Text('Desmentido')),
                        DropdownMenuItem(value: 'rejeitado',  child: Text('Arquivar/Remover')),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
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
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOVO: escolha de penalização ao "Arquivar/Remover" um caso já aprovado.
// Mesmo padrão do diálogo de apagar comentários — o admin decide caso a
// caso, com "sem penalização" como opção explícita, em vez de uma regra
// fixa que estaria sistematicamente errada para metade dos motivos possíveis.
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmarArquivamento extends StatefulWidget {
  const _ConfirmarArquivamento();
  @override
  State<_ConfirmarArquivamento> createState() => _ConfirmarArquivamentoState();
}

class _ConfirmarArquivamentoState extends State<_ConfirmarArquivamento> {
  int _pontos = 0; // por defeito: sem penalização

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Arquivar / Remover Caso',
        style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Este caso já tinha sido aprovado. Porque está a ser arquivado/removido agora?',
            style: TextStyle(color: _C.grey2, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text('Penalização ao autor:',
            style: TextStyle(color: _C.grey2, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...[
            (0,  'Sem penalização — caso legítimo (duplicado, resolvido por outra via, pedido de privacidade)'),
            (15, '−15 pontos — publicado indevidamente'),
            (25, '−25 pontos — fraude descoberta após aprovação'),
          ].map((opt) => RadioListTile<int>(
            value: opt.$1,
            groupValue: _pontos,
            onChanged: (v) => setState(() => _pontos = v!),
            dense: true,
            activeColor: _C.accent,
            title: Text(opt.$2,
              style: TextStyle(color: opt.$1 == 0 ? _C.grey2 : _C.red, fontSize: 12)),
          )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _pontos),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Confirmar', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOVO: detalhes completos do caso + informação do autor, acessíveis
// directamente a partir da tabela "Gerir Casos Ativos" — antes não havia
// nenhuma forma de ver quem publicou nem os dados do caso a partir daqui.
// ─────────────────────────────────────────────────────────────────────────────
class _CaseDetalhesDialog extends StatefulWidget {
  final Map<String, dynamic> caseData;
  final String docId;
  const _CaseDetalhesDialog({required this.caseData, required this.docId});
  @override
  State<_CaseDetalhesDialog> createState() => _CaseDetalhesDialogState();
}

class _CaseDetalhesDialogState extends State<_CaseDetalhesDialog> {
  Map<String, dynamic>? _autor;
  bool _loadingAutor = true;

  @override
  void initState() {
    super.initState();
    _carregarAutor();
  }

  Future<void> _carregarAutor() async {
    final userId = widget.caseData['userId'] as String?;
    if (userId == null || userId.isEmpty) {
      setState(() => _loadingAutor = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (mounted) {
        setState(() {
          _autor = snap.exists ? {'id': snap.id, ...snap.data()!} : null;
          _loadingAutor = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAutor = false);
    }
  }

  String _fmt(dynamic raw) {
    if (raw == null) return '—';
    final dt = raw is Timestamp ? raw.toDate() : DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.caseData;
    final nome     = d['nome'] as String? ?? 'Sem nome';
    final idade    = d['idade']?.toString() ?? '?';
    final sexo     = d['sexo'] as String? ?? '—';
    final roupas   = d['roupas'] as String? ?? '';
    final info     = d['informacoes_adicionais'] as String? ?? '';
    final local    = d['ultimo_local'] as String? ?? '—';
    final prov     = d['provincia'] as String? ?? '—';
    final mun      = d['municipio'] as String? ?? '';
    final dataDesap = _fmt(d['data_desaparecimento']);

    return Dialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _C.border)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _C.purple, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Detalhes do Caso',
                  style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close_rounded, color: _C.grey2), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(color: _C.border, height: 1)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome, style: const TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$idade anos · $sexo', style: const TextStyle(color: _C.grey3, fontSize: 12)),
                    const SizedBox(height: 16),

                    _detalheRow(Icons.location_on_rounded, 'Último local', local, destaque: true),
                    _detalheRow(Icons.map_rounded, 'Local do desaparecimento',
                      [mun, prov].where((s) => s.isNotEmpty).join(', ')),
                    _detalheRow(Icons.calendar_today_rounded, 'Data do desaparecimento', dataDesap),
                    if (roupas.isNotEmpty) _detalheRow(Icons.checkroom_rounded, 'Roupas', roupas),
                    if (info.isNotEmpty) _detalheRow(Icons.notes_rounded, 'Informações adicionais', info),

                    const SizedBox(height: 20),
                    const Text('Autor do relato', style: TextStyle(color: _C.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (_loadingAutor)
                      const Center(child: Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _C.accent))))
                    else if (_autor == null)
                      const Text('Não foi possível encontrar o utilizador que publicou este caso.',
                        style: TextStyle(color: _C.grey3, fontSize: 12))
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_autor!['nome'] as String? ?? _autor!['email'] as String? ?? '—',
                                style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(_autor!['email'] as String? ?? '—', style: const TextStyle(color: _C.grey3, fontSize: 11)),
                            ]),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              showDialog(context: context, builder: (_) => _UserProfileDialog(userData: _autor!));
                            },
                            child: const Text('Ver perfil', style: TextStyle(color: _C.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detalheRow(IconData icon, String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: destaque ? _C.red : _C.grey3),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11)),
              const SizedBox(height: 2),
              Text(valor, style: TextStyle(color: destaque ? _C.red : _C.grey1, fontSize: 13)),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USERS PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _UsersPanel extends StatefulWidget {
  final TextEditingController searchCtrl;
  const _UsersPanel({required this.searchCtrl});
  @override
  State<_UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<_UsersPanel> {
  String _query      = '';
  String _roleFilter = '';
  String _provFilter = '';
  String _ordem      = 'recente';
  DateTime? _dataDe;
  DateTime? _dataAte;
  bool _showFilters  = false;
  List<Map<String, dynamic>> _allUsers = [];
  bool _loading      = true;

  static const _provincias = [
    'Luanda','Benguela','Huambo','Bié','Cabinda','Cuando Cubango',
    'Cuanza Norte','Cuanza Sul','Cunene','Huíla','Lunda Norte',
    'Lunda Sul','Malanje','Moxico','Namibe','Uíge','Zaire',
  ];

  @override
  void initState() {
    super.initState();
    widget.searchCtrl.addListener(_onSearch);
    _fetchUsers();
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onSearch);
    super.dispose();
  }

  void _onSearch() => setState(() => _query = widget.searchCtrl.text.toLowerCase());

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    final snap = await FirebaseFirestore.instance.collection('users').get();
    _allUsers = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _allUsers.where((u) {
      if (_query.isNotEmpty) {
        final haystack = '${u['nome'] ?? ''} ${u['email'] ?? ''} ${u['telefone'] ?? ''}'.toLowerCase();
        if (!haystack.contains(_query)) return false;
      }
      if (_roleFilter.isNotEmpty && (u['role'] ?? 'user') != _roleFilter) return false;
      if (_provFilter.isNotEmpty && (u['provincia'] ?? '').toString().toLowerCase() != _provFilter.toLowerCase()) return false;
      if (_dataDe != null || _dataAte != null) {
        final raw = u['criadoEm'];
        if (raw == null) return _dataDe == null;
        final dt = raw is Timestamp ? raw.toDate() : DateTime.tryParse(raw.toString());
        if (dt == null) return false;
        if (_dataDe != null && dt.isBefore(_dataDe!)) return false;
        if (_dataAte != null && dt.isAfter(_dataAte!.add(const Duration(days: 1)))) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      DateTime? toDate(dynamic raw) {
        if (raw == null) return null;
        if (raw is Timestamp) return raw.toDate();
        return DateTime.tryParse(raw.toString());
      }
      switch (_ordem) {
        case 'recente':   return (toDate(b['criadoEm'])?.millisecondsSinceEpoch ?? 0).compareTo(toDate(a['criadoEm'])?.millisecondsSinceEpoch ?? 0);
        case 'antigo':    return (toDate(a['criadoEm'])?.millisecondsSinceEpoch ?? 0).compareTo(toDate(b['criadoEm'])?.millisecondsSinceEpoch ?? 0);
        case 'nome':      return (a['nome'] ?? '').toString().compareTo((b['nome'] ?? '').toString());
        case 'nome-desc': return (b['nome'] ?? '').toString().compareTo((a['nome'] ?? '').toString());
        default:          return 0;
      }
    });
    return list;
  }

  void _clearFilters() {
    setState(() { _roleFilter = ''; _provFilter = ''; _ordem = 'recente'; _dataDe = null; _dataAte = null; });
    widget.searchCtrl.clear();
  }

  Future<void> _promover(String id, String roleAtual) async {
    final novoRole = roleAtual == 'admin' ? 'user' : 'admin';
    final ok = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(
      title: novoRole == 'admin' ? 'Promover a Admin' : 'Rebaixar para User',
      message: novoRole == 'admin' ? 'Tornar este utilizador Admin?' : 'Remover privilégios de Admin?',
      confirmLabel: novoRole == 'admin' ? 'Promover' : 'Rebaixar',
      confirmColor: novoRole == 'admin' ? _C.accent : _C.orange,
    ));
    if (ok == true) {
      // NOVO: admins não têm Trust Score — remove-o ao promover (some
      // logo da lista de Trust Scores, já filtrada por role) e repõe
      // um valor limpo (100) ao voltar a ser utilizador comum.
      final dados = novoRole == 'admin'
          ? {'role': novoRole, 'trustScore': FieldValue.delete(), 'isSuspended': FieldValue.delete(), 'suspensionReason': FieldValue.delete()}
          : {'role': novoRole, 'trustScore': 100, 'isSuspended': false};
      await FirebaseFirestore.instance.collection('users').doc(id).update(dados);
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Role actualizado para: $novoRole'),
          backgroundColor: _C.green, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(
      title: 'Remover Utilizador',
      message: 'Esta ação não pode ser desfeita. Deseja continuar?',
      confirmLabel: 'Remover', confirmColor: _C.red,
    ));
    if (ok == true) {
      await FirebaseFirestore.instance.collection('users').doc(id).delete();
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Utilizador removido'), backgroundColor: _C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _pickDate(bool isDe) async {
    final picked = await showDatePicker(
      context: context, initialDate: DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: _C.accent, surface: _C.card)),
        child: child!,
      ),
    );
    if (picked != null) setState(() { if (isDe) { _dataDe = picked; } else { _dataAte = picked; } });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingWidget();
    final filtered = _filtered;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionTitle('Utilizadores', subtitle: '${_allUsers.length} registados no total')),
              _IconBtn(
                icon: _showFilters ? Icons.filter_list_off_rounded : Icons.filter_list_rounded,
                color: _showFilters ? _C.accent : _C.grey2,
                bg: _showFilters ? _C.accentSoft : _C.card,
                onTap: () => setState(() => _showFilters = !_showFilters),
              ),
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 16),
            _FiltersPanel(
              roleFilter: _roleFilter, provFilter: _provFilter, ordem: _ordem,
              dataDe: _dataDe, dataAte: _dataAte, provincias: _provincias,
              onRoleChanged: (v) => setState(() => _roleFilter = v),
              onProvChanged: (v) => setState(() => _provFilter = v),
              onOrdemChanged: (v) => setState(() => _ordem = v),
              onPickDe: () => _pickDate(true), onPickAte: () => _pickDate(false),
              onClear: _clearFilters,
            ),
          ],
          const SizedBox(height: 12),
          if (filtered.length != _allUsers.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${filtered.length} utilizador${filtered.length != 1 ? 'es' : ''} encontrado${filtered.length != 1 ? 's' : ''}',
                style: const TextStyle(color: _C.grey2, fontSize: 12)),
            ),
          Expanded(
            child: filtered.isEmpty
              ? _empty('Nenhum utilizador encontrado.')
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = filtered[i];
                    return _UserCard(
                      userData: u, docId: u['id'],
                      onDelete: () => _delete(u['id']),
                      onPromote: () => _promover(u['id'], u['role'] ?? 'user'),
                      onViewProfile: () => showDialog(
                        context: context,
                        builder: (_) => _UserProfileDialog(userData: u),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  final String roleFilter, provFilter, ordem;
  final DateTime? dataDe, dataAte;
  final List<String> provincias;
  final void Function(String) onRoleChanged, onProvChanged, onOrdemChanged;
  final VoidCallback onPickDe, onPickAte, onClear;

  const _FiltersPanel({
    required this.roleFilter, required this.provFilter, required this.ordem,
    required this.dataDe, required this.dataAte, required this.provincias,
    required this.onRoleChanged, required this.onProvChanged, required this.onOrdemChanged,
    required this.onPickDe, required this.onPickAte, required this.onClear,
  });

  String _fmt(DateTime? d) => d == null ? 'Selecionar' : '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filtros', style: TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _FilterDropdown(label: 'Função', value: roleFilter,
              items: const {'': 'Todos', 'user': 'Utilizador', 'admin': 'Admin'}, onChanged: onRoleChanged)),
            const SizedBox(width: 10),
            Expanded(child: _FilterDropdown(label: 'Ordenar', value: ordem,
              items: const {'recente': 'Mais recente', 'antigo': 'Mais antigo', 'nome': 'Nome A→Z', 'nome-desc': 'Nome Z→A'},
              onChanged: onOrdemChanged)),
          ]),
          const SizedBox(height: 10),
          _FilterDropdown(label: 'Província', value: provFilter,
            items: {'': 'Todas', for (final p in provincias) p: p}, onChanged: onProvChanged),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _DateBtn(label: 'Cadastro de', value: _fmt(dataDe), onTap: onPickDe)),
            const SizedBox(width: 10),
            Expanded(child: _DateBtn(label: 'Até', value: _fmt(dataAte), onTap: onPickAte)),
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onClear,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.clear_all_rounded, color: _C.grey2, size: 16),
                SizedBox(width: 6),
                Text('Limpar Filtros', style: TextStyle(color: _C.grey2, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label, value;
  final Map<String, String> items;
  final void Function(String) onChanged;
  const _FilterDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, isExpanded: true, dropdownColor: _C.cardHover,
              style: const TextStyle(color: _C.grey1, fontSize: 13),
              onChanged: (v) { if (v != null) onChanged(v); },
              items: items.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateBtn extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _DateBtn({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, color: _C.grey3, size: 13),
              const SizedBox(width: 6),
              Expanded(child: Text(value, style: const TextStyle(color: _C.grey1, fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String docId;
  final VoidCallback onDelete, onPromote, onViewProfile;
  const _UserCard({
    required this.userData, required this.docId,
    required this.onDelete, required this.onPromote, required this.onViewProfile,
  });

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Desconhecido';
    DateTime dt;
    if (raw is Timestamp) { dt = raw.toDate(); }
    else { dt = DateTime.tryParse(raw.toString()) ?? DateTime.now(); }
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  // NOVO: antes este cartão nunca lia photoBase64 — mostrava sempre um
  // avatar de letra, mesmo quando o utilizador tinha uma foto real definida.
  Uint8List? _decodeFoto(String? b64) {
    if (b64 == null || !b64.contains(',')) return null;
    try { return base64Decode(b64.split(',').last); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final email    = userData['email'] ?? '';
    final nome     = userData['nome']  ?? email;
    final role     = (userData['role'] ?? 'user') as String;
    final isAdmin  = role == 'admin';
    final date     = _formatDate(userData['ultimoLogin'] ?? userData['criadoEm']);
    final isActive = userData['ultimoLogin'] != null;
    final letter   = email.isNotEmpty ? email[0].toUpperCase() : '?';
    final prov     = userData['provincia'] as String?;
    final temGPS   = userData['lat'] != null && userData['lng'] != null;
    final foto     = _decodeFoto(userData['photoBase64'] as String?);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: foto == null
                  ? LinearGradient(colors: isAdmin ? [const Color(0xFF4F7EFF), const Color(0xFF9B5DE5)] : [_C.grey4, _C.grey3])
                  : null,
              borderRadius: BorderRadius.circular(12),
              image: foto != null ? DecorationImage(image: MemoryImage(foto), fit: BoxFit.cover) : null,
            ),
            child: foto == null
                ? Center(child: Text(letter, style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold, fontSize: 18)))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(nome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: isAdmin ? _C.accentSoft : _C.border, borderRadius: BorderRadius.circular(6)),
                    child: Text(role.toUpperCase(), style: TextStyle(color: isAdmin ? _C.accent : _C.grey2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(email, style: const TextStyle(color: _C.grey3, fontSize: 12), overflow: TextOverflow.ellipsis),
                if (prov != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 11, color: _C.grey3),
                    const SizedBox(width: 3),
                    Text(prov, style: const TextStyle(color: _C.grey3, fontSize: 11)),
                    const SizedBox(width: 8),
                    Icon(temGPS ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, size: 11, color: temGPS ? _C.green : _C.grey3),
                    const SizedBox(width: 3),
                    Text(temGPS ? 'GPS' : 'Sem GPS', style: TextStyle(color: temGPS ? _C.green : _C.grey3, fontSize: 11)),
                  ]),
                ],
                const SizedBox(height: 5),
                Row(children: [
                  Icon(isActive ? Icons.circle : Icons.radio_button_unchecked, size: 8, color: isActive ? _C.green : _C.grey3),
                  const SizedBox(width: 5),
                  Expanded(child: Text(isActive ? 'Ativo · $date' : 'Novo · $date',
                    style: TextStyle(color: isActive ? _C.green : _C.grey3, fontSize: 11), overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(children: [
            // ── NOVO: botão "Ver perfil" — equivalente ao link
            // profile.html?uid=... que já existe no admin web.
            GestureDetector(
              onTap: onViewProfile,
              child: Container(
                width: 34, height: 34, margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: _C.purpleSoft, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.purple.withOpacity(0.2))),
                child: const Icon(Icons.visibility_rounded, color: _C.purple, size: 16),
              ),
            ),
            GestureDetector(
              onTap: onPromote,
              child: Container(
                width: 34, height: 34, margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isAdmin ? _C.orangeSoft : _C.accentSoft, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (isAdmin ? _C.orange : _C.accent).withOpacity(0.2))),
                child: Icon(isAdmin ? Icons.person_remove_rounded : Icons.admin_panel_settings_rounded, color: isAdmin ? _C.orange : _C.accent, size: 16),
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: _C.redSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.red.withOpacity(0.2))),
                child: const Icon(Icons.delete_outline_rounded, color: _C.red, size: 16),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// VER PERFIL DO UTILIZADOR (mobile) — equivalente ao profile.html?uid=...
// que já existe no admin web. Mostra os dados completos do utilizador
// num modal, sem depender de uma tela externa de perfil.
// ─────────────────────────────────────────────────────────────────────────────
class _UserProfileDialog extends StatelessWidget {
  final Map<String, dynamic> userData;
  const _UserProfileDialog({required this.userData});

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    else dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Uint8List? _decodeFoto(String? b64) {
    if (b64 == null || !b64.contains(',')) return null;
    try { return base64Decode(b64.split(',').last); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final nome     = userData['nome'] as String? ?? userData['email'] as String? ?? 'Sem nome';
    final email    = userData['email'] as String? ?? '—';
    final role     = (userData['role'] ?? 'user') as String;
    final isAdmin  = role == 'admin';
    final telefone = userData['telefone'] as String?;
    final provincia = userData['provincia'] as String?;
    final municipio  = userData['municipio'] as String?;
    final criadoEm   = _formatDate(userData['criadoEm']);
    final ultimoLogin = _formatDate(userData['ultimoLogin']);
    final verificado  = userData['emailVerificado'] != false;
    final temGPS      = userData['lat'] != null && userData['lng'] != null;
    final foto        = _decodeFoto(userData['photoBase64'] as String?);
    final stats        = userData['stats'] as Map<String, dynamic>? ?? {};
    final apoios        = stats['apoios']?.toString()      ?? '0';
    final comentarios    = stats['comentarios']?.toString() ?? '0';
    final partilhas      = stats['partilhas']?.toString()   ?? '0';
    final letter = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Dialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _C.border)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Cabeçalho ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(children: [
                const Icon(Icons.badge_rounded, color: _C.accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Perfil do Utilizador',
                  style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: _C.grey2),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: _C.border, height: 1),
            ),

            // ── Conteúdo com scroll ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + nome + role
                    Row(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          gradient: foto == null
                              ? LinearGradient(colors: isAdmin
                                  ? [const Color(0xFF4F7EFF), const Color(0xFF9B5DE5)]
                                  : [_C.grey4, _C.grey3])
                              : null,
                          shape: BoxShape.circle,
                          image: foto != null ? DecorationImage(image: MemoryImage(foto), fit: BoxFit.cover) : null,
                        ),
                        child: foto == null
                            ? Center(child: Text(letter, style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold, fontSize: 22)))
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 17)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: isAdmin ? _C.accentSoft : _C.border, borderRadius: BorderRadius.circular(6)),
                                child: Text(role.toUpperCase(), style: TextStyle(color: isAdmin ? _C.accent : _C.grey2, fontSize: 10, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: verificado ? _C.greenSoft : _C.orangeSoft, borderRadius: BorderRadius.circular(6)),
                                child: Text(verificado ? '✓ Verificado' : '⚠ Não verificado',
                                  style: TextStyle(color: verificado ? _C.green : _C.orange, fontSize: 9, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ]),

                    const SizedBox(height: 20),

                    // Stats rápidas
                    Row(children: [
                      Expanded(child: _profileStat('Apoios', apoios, Icons.favorite_rounded, _C.red)),
                      const SizedBox(width: 8),
                      Expanded(child: _profileStat('Comentários', comentarios, Icons.mode_comment_rounded, _C.accent)),
                      const SizedBox(width: 8),
                      Expanded(child: _profileStat('Partilhas', partilhas, Icons.send_rounded, _C.purple)),
                    ]),

                    const SizedBox(height: 20),

                    // Dados de contacto
                    _profileSection('Contacto'),
                    _profileField(Icons.email_rounded, 'Email', email),
                    if (telefone != null && telefone.isNotEmpty)
                      _profileField(Icons.phone_rounded, 'Telefone', telefone),

                    const SizedBox(height: 16),

                    // Localização
                    _profileSection('Localização'),
                    if (provincia != null)
                      _profileField(Icons.map_rounded, 'Província / Município',
                        [provincia, municipio].where((s) => s != null && s.isNotEmpty).join(', ')),
                    _profileField(
                      temGPS ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                      'GPS',
                      temGPS ? 'Localização activa' : 'Sem localização partilhada',
                      destaque: temGPS,
                    ),

                    const SizedBox(height: 16),

                    // Conta
                    _profileSection('Conta'),
                    _profileField(Icons.calendar_today_rounded, 'Registado em', criadoEm),
                    _profileField(Icons.login_rounded, 'Último acesso', ultimoLogin),
                    _profileField(Icons.fingerprint_rounded, 'ID do utilizador', userData['id']?.toString() ?? '—'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: Column(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _C.grey3, fontSize: 10), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _profileSection(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: const TextStyle(color: _C.accent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    );
  }

  Widget _profileField(IconData icon, String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: destaque ? _C.green : _C.grey3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11)),
                const SizedBox(height: 2),
                Text(valor, style: TextStyle(color: destaque ? _C.green : _C.grey1, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// APPROVALS PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _ApprovalsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('casos_pendentes').snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _loadingWidget();
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 80, height: 80, decoration: const BoxDecoration(color: _C.greenSoft, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: _C.green, size: 40)),
            const SizedBox(height: 16),
            const Text('Tudo em dia!', style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Nenhuma aprovação pendente.', style: TextStyle(color: _C.grey3)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 20),
              child: _SectionTitle('Aprovações Pendentes', subtitle: '${docs.length} caso(s) aguardando revisão'));
            return Padding(padding: const EdgeInsets.only(bottom: 14), child: _ApprovalCard(doc: docs[i - 1]));
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
  bool _expanded = false, _approving = false, _rejecting = false;
  Map<String, dynamic>? _relatorData;
  bool _loadingRelator = false;

  @override
  void initState() { super.initState(); _loadRelator(); }

  Future<void> _loadRelator() async {
    final userId = d['userId'] as String?;
    if (userId == null || userId.isEmpty) return;
    setState(() => _loadingRelator = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (snap.exists && mounted) setState(() { _relatorData = snap.data(); _loadingRelator = false; });
    } catch (_) { if (mounted) setState(() => _loadingRelator = false); }
  }

  Map<String, dynamic> get d => widget.doc.data() as Map<String, dynamic>;

  String _formatDate(dynamic raw) {
    if (raw == null) return 'N/A';
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    else if (raw is String) dt = DateTime.tryParse(raw);
    if (dt == null) return 'N/A';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }

  String _daysAgo() {
    final raw = d['data_desaparecimento'];
    if (raw == null) return '';
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    else if (raw is String) dt = DateTime.tryParse(raw);
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
      await FirebaseFirestore.instance.collection('casos').add(data);
      await FirebaseFirestore.instance.collection('casos_pendentes').doc(widget.doc.id).delete();
      await NotificationService.instance.enviarAlertaDesaparecido(
        nome: d['nome'] as String? ?? '', provincia: d['provincia'] as String? ?? '',
        municipio: d['municipio'] as String? ?? '', ultimoLocal: d['ultimo_local'] as String? ?? '',
        idade: d['idade']?.toString() ?? '', sexo: d['sexo'] as String? ?? '',
        roupas: d['roupas'] as String? ?? '', informacoes: d['informacoes_adicionais'] as String? ?? '',
        casoId: widget.doc.id, autorUserId: d['userId'] as String? ?? '',
        imagemBase64: d['imagem'] as String?,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Caso aprovado e alerta enviado!'), backgroundColor: _C.green, behavior: SnackBarBehavior.floating));
    } catch (e) {
      setState(() => _approving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'), backgroundColor: _C.red, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _rejeitar() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ConfirmDialog(
      title: 'Rejeitar Caso', message: 'O caso será removido e não aparecerá no mapa.',
      confirmLabel: 'Rejeitar', confirmColor: _C.red));
    if (ok != true || !mounted) return;
    setState(() => _rejecting = true);
    try {
      await FirebaseFirestore.instance.collection('casos_pendentes').doc(widget.doc.id).delete();

      // ── Penalizar o autor do caso rejeitado ──────────────────────
      final autorIdRej = d['userId'] as String? ?? '';
      if (autorIdRej.isNotEmpty) {
        await TrustService.instance.penalizar(
          uid:      autorIdRej,
          motivo:   'caso_rejeitado',
          pontos:   TrustService.pCasoRejeitado,
          adminUid: FirebaseAuth.instance.currentUser?.uid,
          detalhe:  'Caso removido pelo administrador (rejeitado)',
        );
      }
      // ─────────────────────────────────────────────────────────────

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Caso rejeitado e removido.'), backgroundColor: _C.red, behavior: SnackBarBehavior.floating));
    } catch (e) {
      setState(() => _rejecting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'), backgroundColor: _C.red, behavior: SnackBarBehavior.floating));
    }
  }

  // NOVO: antes este avatar era sempre um ícone fixo — nunca lia o campo
  // 'imagem', que é onde a foto da pessoa desaparecida realmente fica
  // guardada (definida em create_caso_dialog.dart ao submeter o caso).
  Uint8List? get _fotoBytes {
    final img = d['imagem'] as String? ?? '';
    if (!img.startsWith('data:image')) return null;
    try { return base64Decode(img.split(',').last); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final dias = _daysAgo();
    final prov = d['provincia'] ?? d['municipio'] ?? 'Local desconhecido';
    final foto = _fotoBytes;
    return Container(
      decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _C.border)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: _C.accentSoft,
                borderRadius: BorderRadius.circular(14),
                image: foto != null ? DecorationImage(image: MemoryImage(foto), fit: BoxFit.cover) : null,
              ),
              child: foto == null ? const Icon(Icons.person_rounded, color: _C.accent, size: 28) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['nome'] ?? 'Nome Desconhecido',
                style: const TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Row(children: [
                _Chip('${d['idade'] ?? '?'} anos', _C.grey3, _C.border),
                const SizedBox(width: 6),
                _Chip(d['sexo'] ?? '—', _C.grey3, _C.border),
              ]),
            ])),
            _RoundIconBtn(icon: Icons.close_rounded, color: _C.red, bg: _C.redSoft,
              onTap: _rejecting ? null : _rejeitar, loading: _rejecting),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 14, color: _C.grey3),
            const SizedBox(width: 4),
            Text('$prov${dias.isNotEmpty ? " · $dias" : ""}', style: const TextStyle(color: _C.grey3, fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          if (_loadingRelator)
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
              child: const Row(children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: _C.grey3)),
                SizedBox(width: 8),
                Text('Carregando perfil do relator...', style: TextStyle(color: _C.grey3, fontSize: 12)),
              ]))
          else if (_relatorData != null || d['userId'] != null)
            _RelatorCard(relatorData: _relatorData, userId: d['userId'] as String?),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: _C.grey2),
                const SizedBox(width: 8),
                const Text('Ver detalhes completos', style: TextStyle(color: _C.grey2, fontSize: 13)),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: _C.grey3, size: 18),
              ]),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DetailRow('Roupas', d['roupas'] ?? 'N/A'),
                _DetailRow('Data',   _formatDate(d['data_desaparecimento'])),
                _DetailRow('Local',  d['ultimo_local'] ?? 'N/A'),
                _DetailRow('BI',     d['bi'] ?? 'N/A'),
                Divider(color: _C.border, height: 16),
                Text(d['informacoes_adicionais'] ?? 'Sem informações adicionais.',
                  style: const TextStyle(color: _C.grey2, fontSize: 13, height: 1.5)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _ActionBtn(label: 'Rejeitar', icon: Icons.close_rounded,
              color: _C.red, bg: _C.redSoft, border: _C.red.withOpacity(0.3),
              loading: _rejecting, onTap: _rejeitar)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _ActionBtn(label: 'Aprovar + Alertar', icon: Icons.notifications_active_rounded,
              color: _C.white, bg: _C.accent, border: _C.accent,
              loading: _approving, onTap: _aprovar)),
          ]),
        ]),
      ),
    );
  }
}

class _RelatorCard extends StatelessWidget {
  final Map<String, dynamic>? relatorData;
  final String? userId;
  const _RelatorCard({this.relatorData, this.userId});

  String _membroDesde(dynamic raw) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    else if (raw is String) dt = DateTime.tryParse(raw);
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final rNome  = relatorData?['nome']      as String? ?? 'Utilizador desconhecido';
    final rEmail = relatorData?['email']     as String? ?? '—';
    final rProv  = relatorData?['provincia'] as String?;
    final rMembro = _membroDesde(relatorData?['criadoEm']);
    final verificado = (relatorData?['emailVerificado']) != false;
    final letter = rEmail.isNotEmpty ? rEmail[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.person_pin_circle_rounded, size: 13, color: _C.grey3),
          SizedBox(width: 5),
          Text('Relatado por', style: TextStyle(color: _C.grey3, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: _C.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(letter, style: const TextStyle(color: _C.accent, fontWeight: FontWeight.bold, fontSize: 16)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(rNome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: verificado ? _C.greenSoft : _C.orangeSoft, borderRadius: BorderRadius.circular(5)),
                child: Text(verificado ? '✓ Verificado' : '⚠ Não verificado',
                  style: TextStyle(color: verificado ? _C.green : _C.orange, fontSize: 9, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(rEmail, style: const TextStyle(color: _C.grey3, fontSize: 11), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 10, color: _C.grey3),
              const SizedBox(width: 3),
              Text('Membro desde $rMembro', style: const TextStyle(color: _C.grey3, fontSize: 10)),
              if (rProv != null) ...[
                const Text(' · ', style: TextStyle(color: _C.grey3, fontSize: 10)),
                Text(rProv, style: const TextStyle(color: _C.grey3, fontSize: 10)),
              ],
            ]),
          ])),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAPA DE CASOS ADMIN
// ─────────────────────────────────────────────────────────────────────────────
class _MapaAdminPanel extends StatefulWidget {
  @override
  State<_MapaAdminPanel> createState() => _MapaAdminPanelState();
}

class _MapaAdminPanelState extends State<_MapaAdminPanel> {
  final Set<Marker> _markers = {};
  List<Map<String, dynamic>> _casos = [];
  bool _loading = true;
  int _ativos = 0, _encontrados = 0, _desmentidos = 0;
  // NOVO: filtro de status dos marcadores — 'todos' | 'aprovado' | 'encontrado' | 'desmentido'
  String _filtro = 'todos';
  static const _center = LatLng(-11.2027, 17.8739);

  @override
  void initState() { super.initState(); _loadCasos(); }

  Future<void> _loadCasos() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('casos')
          .where('status', whereIn: ['aprovado', 'encontrado', 'desmentido']).get();
      _casos = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _buildMarkers();
    } catch (e) { debugPrint('Erro mapa: $e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _buildMarkers() {
    _markers.clear(); _ativos = 0; _encontrados = 0; _desmentidos = 0;
    for (final caso in _casos) {
      // Os totais dos cartões contam sempre TODOS os casos, mesmo que o
      // filtro esconda alguns marcadores do mapa.
      switch (caso['status']) {
        case 'encontrado': _encontrados++; break;
        case 'desmentido': _desmentidos++; break;
        default: _ativos++;
      }
      if (_filtro != 'todos' && caso['status'] != _filtro) continue;

      double? lat = double.tryParse(caso['lat']?.toString() ?? '');
      double? lng = double.tryParse(caso['lng']?.toString() ?? '');
      if (lat == null || lng == null) {
        final coords = provCoords[(caso['provincia'] ?? '').toString().toLowerCase()];
        if (coords == null) continue;
        lat = coords.latitude  + (DateTime.now().microsecond % 10 - 5) * 0.06;
        lng = coords.longitude + (DateTime.now().microsecond % 10 - 5) * 0.06;
      }
      final status = caso['status'] as String? ?? 'aprovado';
      final icon = status == 'encontrado'
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : status == 'desmentido'
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      _markers.add(Marker(
        markerId: MarkerId(caso['id']),
        position: LatLng(lat, lng),
        icon: icon,
        infoWindow: InfoWindow(title: caso['nome'] ?? 'Desconhecido',
          snippet: '${caso['municipio'] ?? caso['provincia'] ?? 'Angola'} · $status'),
      ));
    }
    if (mounted) setState(() {});
  }

  void _aplicarFiltro(String f) {
    setState(() => _filtro = f);
    _buildMarkers();
  }

  void _openEditarLocalizacao() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _EditarLocalizacaoSheet(onSaved: _loadCasos));
  }

  Widget _filtroChip(String valor, String label) {
    final ativo = _filtro == valor;
    return GestureDetector(
      onTap: () => _aplicarFiltro(valor),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: ativo ? _C.accent : _C.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? _C.accent : _C.border),
        ),
        child: Text(label, style: TextStyle(color: ativo ? _C.white : _C.grey2, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CORRIGIDO: a versão anterior usava Expanded(flex:3) dentro de uma
    // Column sem scroll — em ecrãs pequenos ou com letra maior, o resto
    // do conteúdo (título, legenda, cartões) já não cabia e estourava
    // ("bottom overflowed"). Agora é SingleChildScrollView com o mapa em
    // altura fixa: nunca pode estourar, no máximo faz scroll.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _SectionTitle('Mapa de Casos', subtitle: 'Localização geográfica de todos os casos aprovados')),
          GestureDetector(
            onTap: _openEditarLocalizacao,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _C.orangeSoft, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.orange.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.edit_location_rounded, color: _C.orange, size: 15),
                SizedBox(width: 6),
                Text('Corrigir', style: TextStyle(color: _C.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _LegendaDot(color: _C.accent, label: 'Activo'),
          const SizedBox(width: 16),
          _LegendaDot(color: _C.green,  label: 'Encontrado'),
          const SizedBox(width: 16),
          _LegendaDot(color: Colors.blueGrey, label: 'Desmentido'),
        ]),
        const SizedBox(height: 14),
        // NOVO: filtro de status dos casos mostrados no mapa — mesma
        // ideia dos filtros de casos do web, aplicado aqui aos marcadores.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filtroChip('todos', 'Todos'),
            _filtroChip('aprovado', 'Activos'),
            _filtroChip('encontrado', 'Encontrados'),
            _filtroChip('desmentido', 'Desmentidos'),
          ]),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 340,
            child: _loading
              ? Container(color: _C.card, child: const Center(child: CircularProgressIndicator(color: _C.accent)))
              : GoogleMap(initialCameraPosition: const CameraPosition(target: _center, zoom: 5),
                  markers: _markers, mapType: MapType.normal,
                  myLocationButtonEnabled: false, zoomControlsEnabled: true),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _MapStatCard(label: 'Total',       count: _casos.length, color: _C.grey2,  colorSoft: _C.border)),
          const SizedBox(width: 10),
          Expanded(child: _MapStatCard(label: 'Activos',     count: _ativos,       color: _C.accent, colorSoft: _C.accentSoft)),
          const SizedBox(width: 10),
          Expanded(child: _MapStatCard(label: 'Encontrados', count: _encontrados,  color: _C.green,  colorSoft: _C.greenSoft)),
        ]),
      ]),
    );
  }
}

class _LegendaDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendaDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(color: _C.grey2, fontSize: 12)),
  ]);
}

class _MapStatCard extends StatelessWidget {
  final String label; final int count; final Color color, colorSoft;
  const _MapStatCard({required this.label, required this.count, required this.color, required this.colorSoft});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: colorSoft, borderRadius: BorderRadius.circular(8)),
        child: Center(child: Icon(Icons.location_on_rounded, color: color, size: 16))),
      const SizedBox(height: 8),
      Text('$count', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: _C.grey2, fontSize: 11)),
    ]),
  );
}

class _EditarLocalizacaoSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _EditarLocalizacaoSheet({required this.onSaved});
  @override
  State<_EditarLocalizacaoSheet> createState() => _EditarLocalizacaoSheetState();
}

class _EditarLocalizacaoSheetState extends State<_EditarLocalizacaoSheet> {
  // ── ALTERADO: lista TODOS os casos (não só os sem coordenadas) ──────────
  // Agora o admin pode corrigir/mover a localização de QUALQUER caso,
  // não apenas dos que ainda não têm lat/lng definidos.
  List<Map<String, dynamic>> _todosCasos = [];
  Map<String, dynamic>? _selectedCaso;
  LatLng? _selectedLatLng;
  bool _loadingCasos = true, _saving = false;
  GoogleMapController? _editMapCtrl;
  final Set<Marker> _editMarkers = {};

  // Quantos casos já têm coordenadas vs quantos ainda não têm
  int get _comCoord  => _todosCasos.where(_temCoordValidas).length;
  int get _semCoord  => _todosCasos.length - _comCoord;

  bool _temCoordValidas(Map<String, dynamic> c) {
    final lat = c['lat'];
    final lng = c['lng'];
    if (lat == null || lng == null) return false;
    if (lat.toString().isEmpty || lng.toString().isEmpty) return false;
    return double.tryParse(lat.toString()) != null && double.tryParse(lng.toString()) != null;
  }

  // ── NOVO: guarda a mensagem de erro para mostrar na UI em vez de
  // engolir silenciosamente — assim conseguimos ver POR QUE a lista
  // de casos aparece vazia (ex: índice do Firestore em falta, regras
  // de segurança a bloquear, sem ligação à internet, etc.)
  String? _erroCarregamento;

  @override
  void initState() { super.initState(); _loadTodosCasos(); }

  Future<void> _loadTodosCasos() async {
    setState(() { _loadingCasos = true; _erroCarregamento = null; });
    try {
      final snap = await FirebaseFirestore.instance.collection('casos')
          .where('status', whereIn: ['aprovado', 'encontrado', 'desmentido']).get();
      _todosCasos = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      // ── NOVO: diagnóstico — se a query com filtro voltou vazia,
      // verifica se a coleção 'casos' tem documentos sem esse filtro.
      // Isto distingue "coleção vazia" de "nenhum status combina".
      if (_todosCasos.isEmpty) {
        final snapTodos = await FirebaseFirestore.instance.collection('casos').limit(50).get();
        if (snapTodos.docs.isEmpty) {
          _erroCarregamento = 'A coleção "casos" está vazia — ainda não há casos criados.';
        } else {
          final statusEncontrados = snapTodos.docs
              .map((d) => (d.data()['status'] ?? '«sem status»').toString())
              .toSet()
              .join(', ');
          _erroCarregamento =
              'Há ${snapTodos.docs.length} caso(s) na base de dados, mas nenhum com '
              'status aprovado/encontrado/desmentido. Status encontrados: $statusEncontrados';
        }
      } else {
        // Casos sem localização aparecem primeiro na lista (mais urgentes)
        _todosCasos.sort((a, b) {
          final aTem = _temCoordValidas(a) ? 1 : 0;
          final bTem = _temCoordValidas(b) ? 1 : 0;
          return aTem.compareTo(bTem);
        });
      }
    } catch (e) {
      debugPrint('Erro editar loc: $e');
      _erroCarregamento = e.toString();
    }
    finally { if (mounted) setState(() => _loadingCasos = false); }
  }

  void _selectCaso(Map<String, dynamic> caso) {
    // ── NOVO: se o caso já tem coordenadas, pré-carrega o marcador
    // no mapa nessa posição, em vez de começar vazio — assim o admin
    // vê de imediato onde o caso está marcado actualmente e pode
    // simplesmente tocar num novo ponto para corrigir.
    LatLng? posAtual;
    if (_temCoordValidas(caso)) {
      final lat = double.tryParse(caso['lat'].toString());
      final lng = double.tryParse(caso['lng'].toString());
      if (lat != null && lng != null) posAtual = LatLng(lat, lng);
    }

    setState(() {
      _selectedCaso   = caso;
      _selectedLatLng = posAtual;
      _editMarkers.clear();
      if (posAtual != null) {
        _editMarkers.add(Marker(
          markerId: const MarkerId('sel'),
          position: posAtual,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: caso['nome'] ?? '',
            snippet: 'Localização actual · toque para mover'),
        ));
      }
    });

    if (posAtual != null) {
      _editMapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(posAtual, 13));
    }
  }

  void _onMapTap(LatLng latlng) {
    if (_selectedCaso == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione um caso primeiro.'), backgroundColor: _C.orange, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() {
      _selectedLatLng = latlng;
      _editMarkers..clear()..add(Marker(
        markerId: const MarkerId('sel'), position: latlng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: _selectedCaso!['nome'] ?? '',
          snippet: '${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)}'),
      ));
    });
    _editMapCtrl?.animateCamera(CameraUpdate.newLatLng(latlng));
  }

  Future<void> _salvar() async {
    if (_selectedCaso == null || _selectedLatLng == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('casos').doc(_selectedCaso!['id']).update({
        'lat': _selectedLatLng!.latitude.toString(), 'lng': _selectedLatLng!.longitude.toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Localização de "${_selectedCaso!['nome']}" guardada!'),
          backgroundColor: _C.green, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
        widget.onSaved();
        setState(() { _selectedCaso = null; _selectedLatLng = null; _editMarkers.clear(); });
        _loadTodosCasos();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'), backgroundColor: _C.red, behavior: SnackBarBehavior.floating));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.92,
      decoration: const BoxDecoration(color: _C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 14, bottom: 10), width: 40, height: 4,
          decoration: BoxDecoration(color: _C.grey4, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          const Icon(Icons.edit_location_alt_rounded, color: _C.orange, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Editar Localização dos Casos', style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: _C.grey2)),
        ])),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(
          _loadingCasos
              ? 'A carregar casos...'
              : '${_todosCasos.length} caso${_todosCasos.length != 1 ? 's' : ''} no total · $_comCoord com GPS · $_semCoord sem GPS',
          style: const TextStyle(color: _C.grey3, fontSize: 12))),
        const SizedBox(height: 14),
        Expanded(child: _loadingCasos
          ? const Center(child: CircularProgressIndicator(color: _C.accent))
          // ── NOVO: mostra o erro/diagnóstico real em vez de "nenhum caso" genérico ──
          : _erroCarregamento != null
            ? Center(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 60, height: 60, decoration: const BoxDecoration(color: _C.orangeSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.info_outline_rounded, color: _C.orange, size: 30)),
                  const SizedBox(height: 12),
                  const Text('Não foi possível listar os casos', style: TextStyle(color: _C.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(_erroCarregamento!, textAlign: TextAlign.center,
                    style: const TextStyle(color: _C.grey3, fontSize: 11)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadTodosCasos,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Tentar novamente'),
                    style: ElevatedButton.styleFrom(backgroundColor: _C.accent, foregroundColor: _C.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ]),
              ))
          : _todosCasos.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 60, height: 60, decoration: const BoxDecoration(color: _C.greenSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded, color: _C.green, size: 30)),
                const SizedBox(height: 12),
                const Text('Nenhum caso activo encontrado.', style: TextStyle(color: _C.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('Casos precisam de status: aprovado, encontrado ou desmentido.',
                  style: TextStyle(color: _C.grey3, fontSize: 11)),
              ]))
            // CORRIGIDO: a versão anterior calculava a altura do mapa à
            // mão (LayoutBuilder + números fixos "adivinhados" para a
            // lista e a caixa de status) — se o texto ocupasse uma linha
            // a mais em qualquer ecrã, a conta errava e voltava a
            // estourar. Expanded resolve isto sozinho: ocupa sempre o
            // espaço que sobra, nunca mais nem menos, sem cálculo nenhum.
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(left: 20, bottom: 6),
                  child: Text('Selecionar caso  ·  toque para editar a localização', style: TextStyle(color: _C.grey2, fontSize: 12, fontWeight: FontWeight.w600))),
                SizedBox(height: 72, child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal, itemCount: _todosCasos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = _todosCasos[i];
                    final isSelected = _selectedCaso?['id'] == c['id'];
                    final temGPS = _temCoordValidas(c);
                    return GestureDetector(
                      onTap: () => _selectCaso(c),
                      // Largura fixa (180) — dentro de um ListView
                      // horizontal, um Row/Flexible sem largura definida
                      // tenta ocupar largura infinita e causa overflow.
                      // Com width fixo o texto interno tem um limite
                      // real para fazer ellipsis.
                      child: SizedBox(
                        width: 180,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? _C.accentSoft : _C.card, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? _C.accent : _C.border, width: isSelected ? 1.5 : 1)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Row(children: [
                              Expanded(child: Text(c['nome'] ?? 'Sem nome',
                                style: TextStyle(color: isSelected ? _C.accent : _C.white, fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 5),
                              // ── indicador se o caso já tem GPS ou não ──
                              Icon(temGPS ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                                size: 11, color: temGPS ? _C.green : _C.orange),
                            ]),
                            const SizedBox(height: 3),
                            Row(children: [
                              Icon(Icons.location_on_rounded, size: 11, color: isSelected ? _C.accent : _C.grey3),
                              const SizedBox(width: 3),
                              Expanded(child: Text(c['municipio'] ?? c['provincia'] ?? '—',
                                style: TextStyle(color: isSelected ? _C.accent.withOpacity(0.8) : _C.grey3, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                )),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200), width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _selectedCaso != null ? _C.accent.withOpacity(0.4) : _C.border)),
                  child: Row(children: [
                    Icon(_selectedCaso != null ? Icons.edit_location_alt_rounded : Icons.touch_app_rounded,
                      color: _selectedCaso != null ? _C.accent : _C.grey3, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: _selectedCaso == null
                      ? const Text('Selecione um caso acima para começar', style: TextStyle(color: _C.grey3, fontSize: 12))
                      : _selectedLatLng != null
                        ? Text('${_selectedCaso!['nome']}  ·  📍 ${_selectedLatLng!.latitude.toStringAsFixed(4)}, ${_selectedLatLng!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: _C.accent, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)
                        : Text('${_selectedCaso!['nome']}  ·  Toque no mapa para definir',
                            style: const TextStyle(color: _C.grey2, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  ]),
                )),
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
                      child: GoogleMap(
                        initialCameraPosition: const CameraPosition(target: LatLng(-11.2027, 17.8739), zoom: 5),
                        onMapCreated: (ctrl) => _editMapCtrl = ctrl, onTap: _onMapTap,
                        markers: _editMarkers, myLocationButtonEnabled: false, zoomControlsEnabled: true),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ]),
        ),
        if (_selectedCaso != null && _selectedLatLng != null)
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: ElevatedButton(
              onPressed: _saving ? null : _salvar,
              style: ElevatedButton.styleFrom(backgroundColor: _C.green, foregroundColor: _C.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _C.white))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.save_rounded, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Guardar localização de "${_selectedCaso!['nome'] ?? '...'}"',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  ]),
            ),
          )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENTES REUTILIZÁVEIS
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;
  const _ConfirmDialog({required this.title, required this.message, required this.confirmLabel, required this.confirmColor});
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _C.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _C.border)),
    title: Text(title, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
    content: Text(message, style: const TextStyle(color: _C.grey2, fontSize: 14, height: 1.5)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: _C.grey2))),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: _C.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
        child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 60, child: Text('$label:', style: const TextStyle(color: _C.grey3, fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: const TextStyle(color: _C.grey1, fontSize: 12))),
    ]),
  );
}

class _Chip extends StatelessWidget {
  final String text; final Color textColor, borderColor;
  const _Chip(this.text, this.textColor, this.borderColor);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: borderColor.withOpacity(0.3), borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor)),
    child: Text(text, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500)),
  );
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon; final Color color, bg; final VoidCallback? onTap; final bool loading;
  const _RoundIconBtn({required this.icon, required this.color, required this.bg, this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
      child: loading
        ? Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)))
        : Icon(icon, color: color, size: 18),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color, bg, border; final bool loading; final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.bg, required this.border, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border.withOpacity(0.4))),
      child: loading
        ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color)))
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: color), const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final Color color, bg; final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

Widget _loadingWidget() => const Center(child: CircularProgressIndicator(color: _C.accent));
Widget _empty(String msg) => Center(child: Text(msg, style: const TextStyle(color: _C.grey3, fontSize: 16)));