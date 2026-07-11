// screens/profile.dart
// Perfil completo — com todas as funcionalidades da versão web
// ATUALIZADO: correção do nome de perfil + edição inline

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'login_page.dart';
import 'home_page.dart';
import '../models/user_mode.dart';
import '../services/notification_service.dart'; // ← NOVO: removerTokenAntesDeSair

// ─── PALETA ─────────────────────────────────────────────
class _C {
  static const bg      = Color(0xFF0D0D0F);
  static const surface = Color(0xFF141418);
  static const card    = Color(0xFF1C1C22);
  static const border  = Color(0xFF2A2A33);
  static const accent  = Color(0xFF4F7EFF);
  static const green   = Color(0xFF22C55E);
  static const orange  = Color(0xFFF59E0B);
  static const red     = Color(0xFFEF4444);
  static const purple  = Color(0xFF9B5DE5);
  static const grey1   = Color(0xFFE4E4E7);
  static const grey2   = Color(0xFFA1A1AA);
  static const grey3   = Color(0xFF52525B);
  static const grey4   = Color(0xFF3F3F46);
  static const white   = Color(0xFFFFFFFF);
}

// ─── EMBLEMAS ──────────────────────────────────────────
class _Badge {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  const _Badge({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });
}

// NOVO: a localização do GPS é guardada em minúsculas em
// localizacaoActual (é assim que a lógica de notificações regionais a
// compara), mas para mostrar no ecrã de Perfil fica mais correcto com
// maiúscula inicial em cada palavra — ex: "luanda" → "Luanda".
String _capitalizarPalavras(String texto) {
  if (texto.isEmpty) return texto;
  return texto
      .split(' ')
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

List<_Badge> _calcularEmblemas(
  Map<String, dynamic> userData,
  int postedCount,
  int supportsGiven,
  int totalApoiosReceived,
) {
  final stats = (userData['stats'] as Map<String, dynamic>?) ?? {};
  final badges = <_Badge>[];

  if (userData['role'] == 'admin') {
    badges.add(const _Badge(
      id: 'admin',
      label: 'Admin',
      icon: Icons.shield_rounded,
      color: Color(0xFFFFD700),
      bg: Color(0x33FFD700),
    ));
  }
  if ((stats['apoios'] as int? ?? 0) >= 5) {
    badges.add(const _Badge(
      id: 'apoiador',
      label: 'Apoiador',
      icon: Icons.volunteer_activism_rounded,
      color: _C.red,
      bg: Color(0x26EF4444),
    ));
  }
  if ((stats['comentarios'] as int? ?? 0) >= 5) {
    badges.add(const _Badge(
      id: 'comentador',
      label: 'Comentador',
      icon: Icons.mode_comment_rounded,
      color: _C.accent,
      bg: Color(0x264F7EFF),
    ));
  }
  if ((stats['partilhas'] as int? ?? 0) >= 3) {
    badges.add(const _Badge(
      id: 'partilhador',
      label: 'Partilha',
      icon: Icons.share_rounded,
      color: _C.green,
      bg: Color(0x2622C55E),
    ));
  }
  if (postedCount >= 3) {
    badges.add(const _Badge(
      id: 'publicador',
      label: 'Publicador',
      icon: Icons.assignment_rounded,
      color: _C.orange,
      bg: Color(0x26F59E0B),
    ));
  }
  if (totalApoiosReceived >= 10) {
    badges.add(const _Badge(
      id: 'impacto',
      label: 'Impacto',
      icon: Icons.favorite_rounded,
      color: _C.purple,
      bg: Color(0x269B5DE5),
    ));
  }
  return badges;
}

// ─── PÁGINA PRINCIPAL DO PERFIL ────────────────────────
class ProfileScreen extends StatefulWidget {
  final String? targetUid;
  const ProfileScreen({super.key, this.targetUid});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  late TabController _tabController;

  String? _currentUid;
  String? _targetUid;
  bool _isOwner = false;

  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _meusCasos = [];
  List<Map<String, dynamic>> _casosApoios = [];

  bool _loadingProfile = true;
  bool _uploadingPhoto = false;
  bool _updatingLocation = false;

  // Stats calculadas
  int _statAprovados = 0;
  int _statPendentes = 0;
  int _statApoiosRecebidos = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
      return;
    }
    _currentUid = user.uid;
    _targetUid = widget.targetUid ?? _currentUid;
    _isOwner = _targetUid == _currentUid;

    await _carregarPerfil();
    await Future.wait([_carregarMeusCasos(), _carregarCasosApoiados()]);

    // Registar visita se não for o dono
    if (!_isOwner) {
      _registrarVisita();
    }

    // Atualizar localização automaticamente (apenas dono)
    if (_isOwner) {
      _atualizarLocalizacaoAutomatica();
    }
  }

  // ── Carregar perfil ──────────────────────────────────
  Future<void> _carregarPerfil() async {
    try {
      final snap = await _db.collection('users').doc(_targetUid).get();

      if (snap.exists) {
        final data = snap.data()!;

        // 🔧 CORREÇÃO: Se não tiver nome, tenta buscar do Auth e salvar
        if ((data['nome'] == null || (data['nome'] as String).isEmpty) && _isOwner) {
          final authUser = _auth.currentUser;
          final nomeDoAuth = authUser?.displayName ?? authUser?.email?.split('@').first ?? '';

          if (nomeDoAuth.isNotEmpty) {
            // Atualizar Firestore com o nome
            await _db.collection('users').doc(_targetUid).update({'nome': nomeDoAuth});
            data['nome'] = nomeDoAuth;
          }
        }

        setState(() {
          _userData = data;
          _loadingProfile = false;
        });
      } else {
        // Documento não existe — criar documento básico
        if (_isOwner) {
          final authUser = _auth.currentUser;
          final nomeInicial = authUser?.displayName ??
              authUser?.email?.split('@').first ??
              'Utilizador';

          await _db.collection('users').doc(_targetUid).set({
            'nome': nomeInicial,
            'email': authUser?.email ?? '',
            'role': 'user',
            'criadoEm': FieldValue.serverTimestamp(),
            'visitasCount': 0,
            'photoBase64': '',
            'stats': {'apoios': 0, 'comentarios': 0, 'partilhas': 0},
          });

          setState(() {
            _userData = {
              'nome': nomeInicial,
              'email': authUser?.email ?? '',
              'role': 'user',
              'visitasCount': 0,
              'photoBase64': '',
              'stats': {'apoios': 0, 'comentarios': 0, 'partilhas': 0},
            };
            _loadingProfile = false;
          });
        } else {
          setState(() => _loadingProfile = false);
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
      setState(() => _loadingProfile = false);
    }
  }

  // ── EDITAR NOME (novo) ────────────────────────────────
  Future<void> _editarNome() async {
    if (!_isOwner) return;

    final nomeAtual = (_userData?['nome'] as String?) ?? '';
    final controller = TextEditingController(text: nomeAtual);

    final novoNome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _C.border),
        ),
        title: const Text('Editar Nome',
            style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: _C.white),
          decoration: InputDecoration(
            hintText: 'Seu nome completo',
            hintStyle: const TextStyle(color: _C.grey3),
            filled: true,
            fillColor: _C.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _C.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Salvar',
                style: TextStyle(color: _C.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (novoNome != null && novoNome.isNotEmpty && novoNome != nomeAtual) {
      try {
        await _db.collection('users').doc(_currentUid).update({'nome': novoNome});
        setState(() {
          _userData = {...?_userData, 'nome': novoNome};
        });
        if (mounted) _showToast('✅ Nome atualizado!');
      } catch (e) {
        if (mounted) _showToast('❌ Erro ao salvar nome.');
      }
    }
  }

  // ── Carregar casos ───────────────────────────────────
  Future<void> _carregarMeusCasos() async {
    try {
      final snapPend = await _db
          .collection('casos_pendentes')
          .where('userId', isEqualTo: _targetUid)
          .get();
      final snapAprov = await _db
          .collection('casos')
          .where('userId', isEqualTo: _targetUid)
          .get();

      final todos = <Map<String, dynamic>>[];
      for (final d in snapPend.docs) {
        todos.add({...d.data(), 'id': d.id, '_origem': 'pendente'});
      }
      for (final d in snapAprov.docs) {
        todos.add({...d.data(), 'id': d.id, '_origem': 'casos'});
      }

      int aprovados = 0, pendentes = 0, totalApoios = 0;
      for (final c in todos) {
        final s = c['status'] as String? ?? '';
        if (s == 'aprovado' || s == 'encontrado' || s == 'desmentido') {
          aprovados++;
        } else {
          pendentes++;
        }
        totalApoios += (c['apoios'] as int? ?? 0);
      }

      setState(() {
        _meusCasos = todos;
        _statAprovados = aprovados;
        _statPendentes = pendentes;
        _statApoiosRecebidos = totalApoios;
      });
    } catch (e) {
      debugPrint('Erro ao carregar meus casos: $e');
    }
  }

  // ── Carregar casos apoiados ──────────────────────────
  Future<void> _carregarCasosApoiados() async {
    try {
      final snap = await _db
          .collection('casos')
          .where('apoiadoPor', arrayContains: _targetUid)
          .get();
      setState(() {
        _casosApoios =
            snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      });
    } catch (e) {
      debugPrint('Erro ao carregar apoios: $e');
    }
  }

  // ── Registar visita ──────────────────────────────────
  Future<void> _registrarVisita() async {
    if (_currentUid == null ||
        _targetUid == null ||
        _currentUid == _targetUid) return;
    try {
      await _db
          .collection('users')
          .doc(_targetUid)
          .collection('visitas')
          .add({
        'visitor': _currentUid,
        'at': FieldValue.serverTimestamp(),
      });
      await _db.collection('users').doc(_targetUid).update({
        'visitasCount': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  // ── Atualizar localização automaticamente ────────────
  Future<void> _atualizarLocalizacaoAutomatica() async {
    if (!_isOwner || _currentUid == null) return;

    setState(() => _updatingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _updatingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _updatingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String? provincia;
      String? municipio;

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        provincia = place.administrativeArea;
        municipio = place.subAdministrativeArea ??
            place.locality ??
            place.subLocality;
      }

      // CORRIGIDO: antes gravava em provinciaAtual/municipioAtual — campos
      // que mais nenhum sítio do código lia. O sistema de notificações
      // regionais (notification_service.dart) usa o campo
      // localizacaoActual (um mapa aninhado), gravado só depois do
      // login — o Perfil nunca actualizava esse mesmo campo, por isso o
      // GPS aqui não tinha qualquer efeito nas notificações, e o texto
      // "região" do Perfil também nunca mudava (lia sempre municipio/
      // provincia do cadastro, que são campos diferentes). Agora escreve
      // no MESMO campo localizacaoActual que as notificações já usam —
      // um único ponto de verdade para "onde está o utilizador agora".
      // Mantém também lat/lng à parte, porque o painel admin (mobile e
      // web) usa esses dois campos directamente para mostrar o selo
      // "GPS activa" na lista de utilizadores.
      final localizacaoActual = {
        'lat': position.latitude,
        'lng': position.longitude,
        'municipio': (municipio ?? '').toLowerCase(),
        'provincia': (provincia ?? '').toLowerCase(),
        'timestamp': Timestamp.now(),
      };

      await _db.collection('users').doc(_currentUid).update({
        'lat': position.latitude,
        'lng': position.longitude,
        'localizacaoActual': localizacaoActual,
      });

      // NOVO: actualiza o estado local de imediato — antes só aparecia
      // um toast, mas o texto "região" no ecrã continuava com o valor
      // antigo até se sair e reabrir o perfil.
      if (mounted) {
        setState(() {
          _userData = {
            ...?_userData,
            'lat': position.latitude,
            'lng': position.longitude,
            'localizacaoActual': localizacaoActual,
          };
        });
      }

      if (mounted && (municipio != null || provincia != null)) {
        final local = municipio ?? provincia ?? 'detectada';
        _showToast('📍 Localização actualizada: $local');
      }
    } catch (e) {
      debugPrint('Erro ao atualizar localização: $e');
    } finally {
      if (mounted) setState(() => _updatingLocation = false);
    }
  }

  // ── Alterar foto ─────────────────────────────────────
  Future<void> _alterarFoto() async {
    if (!_isOwner) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 82,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final base64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    setState(() => _uploadingPhoto = true);
    try {
      await _db
          .collection('users')
          .doc(_currentUid)
          .update({'photoBase64': base64});
      setState(() {
        _userData = {...?_userData, 'photoBase64': base64};
      });
      if (mounted) _showToast('✅ Foto actualizada!');
    } catch (e) {
      if (mounted) _showToast('❌ Erro ao guardar foto.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Logout ───────────────────────────────────────────
  Future<void> _logout() async {
    // NOVO: remove o token FCM desta conta antes de sair — evita que a
    // próxima conta a entrar neste aparelho fique a partilhar o mesmo
    // token e esta conta continue a receber notificações depois de sair.
    await NotificationService.instance.removerTokenAntesDeSair();
    await _auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  // ── Toast ────────────────────────────────────────────
  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _C.card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        backgroundColor: _C.bg,
        body: Center(child: CircularProgressIndicator(color: _C.accent)),
      );
    }

    // 🔧 NOME CORRIGIDO — prioridade: Firestore > Auth > email > fallback
    final nome = (_userData?['nome'] as String?)?.isNotEmpty == true
        ? _userData!['nome'] as String
        : (_auth.currentUser?.displayName?.isNotEmpty == true
            ? _auth.currentUser!.displayName!
            : (_auth.currentUser?.email?.isNotEmpty == true
                ? _auth.currentUser!.email!.split('@').first
                : 'Utilizador'));

    final email = _userData?['email'] as String? ??
        _auth.currentUser?.email ??
        '—';

    // CORRIGIDO: antes lia sempre municipio/provincia do CADASTRO,
    // mesmo depois de o utilizador autorizar o GPS — o texto "região"
    // nunca reflectia a localização actual. Agora prefere
    // localizacaoActual (o mesmo campo que as notificações regionais já
    // usam) e só cai para o valor do cadastro se o GPS nunca tiver sido
    // autorizado (localizacaoActual ainda não existe nesse caso).
    final localizacaoActual = _userData?['localizacaoActual'] as Map<String, dynamic>?;
    final municipioGPS = (localizacaoActual?['municipio'] as String? ?? '').trim();
    final provinciaGPS = (localizacaoActual?['provincia'] as String? ?? '').trim();
    final temLocalizacaoGPS = municipioGPS.isNotEmpty || provinciaGPS.isNotEmpty;

    final municipio = temLocalizacaoGPS
        ? _capitalizarPalavras(municipioGPS)
        : (_userData?['municipio'] as String? ?? '');
    final provincia = temLocalizacaoGPS
        ? _capitalizarPalavras(provinciaGPS)
        : (_userData?['provincia'] as String? ?? '');
    final local =
        [municipio, provincia].where((s) => s.isNotEmpty).join(', ');
    final visitas = _userData?['visitasCount'] as int? ?? 0;
    final fotoB64 = _userData?['photoBase64'] as String?;
    final badges = _calcularEmblemas(
      _userData ?? {},
      _meusCasos.length,
      _casosApoios.length,
      _statApoiosRecebidos,
    );

    Uint8List? fotoBytes;
    if (fotoB64 != null && fotoB64.contains(',')) {
      try {
        fotoBytes = base64Decode(fotoB64.split(',').last);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: _buildProfileHeader(
                nome: nome,
                email: email,
                local: local.isEmpty ? 'Localização não definida' : local,
                visitas: visitas,
                fotoBytes: fotoBytes,
                badges: badges,
              ),
            ),
          ],
          body: Column(
            children: [
              // Tabs
              Container(
                decoration: BoxDecoration(
                  color: _C.surface,
                  border: Border(bottom: BorderSide(color: _C.border)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _C.accent,
                  indicatorWeight: 2,
                  labelColor: _C.white,
                  unselectedLabelColor: _C.grey3,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                      text: 'Meus Casos',
                    ),
                    Tab(
                      icon: Icon(Icons.favorite_rounded, size: 18),
                      text: 'Apoios',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGrid(_meusCasos, tipo: 'meus'),
                    _buildGrid(_casosApoios, tipo: 'apoios'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header do perfil ─────────────────────────────────
  Widget _buildProfileHeader({
    required String nome,
    required String email,
    required String local,
    required int visitas,
    required Uint8List? fotoBytes,
    required List<_Badge> badges,
  }) {
    return Container(
      color: _C.surface,
      child: Column(
        children: [
          // Topbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: _C.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                        color: _C.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_isOwner)
                  PopupMenuButton<String>(
                    color: _C.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit_name':
                          await _editarNome();
                          break;
                        case 'photo':
                          await _alterarFoto();
                          break;
                        case 'location':
                          await _atualizarLocalizacaoAutomatica();
                          break;
                        case 'logout':
                          await _logout();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit_name',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                color: _C.orange, size: 18),
                            SizedBox(width: 10),
                            Text('Editar Nome',
                                style: TextStyle(color: _C.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'photo',
                        child: Row(
                          children: [
                            Icon(Icons.image_outlined,
                                color: _C.accent, size: 18),
                            SizedBox(width: 10),
                            Text('Alterar Foto de Perfil',
                                style: TextStyle(color: _C.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'location',
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                color: _C.green, size: 18),
                            SizedBox(width: 10),
                            Text('Actualizar Localização',
                                style: TextStyle(color: _C.white)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout_rounded,
                                color: _C.red, size: 18),
                            SizedBox(width: 10),
                            Text('Sair da Conta',
                                style: TextStyle(color: _C.red)),
                          ],
                        ),
                      ),
                    ],
                    child: const Icon(Icons.more_vert_rounded,
                        color: _C.white),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),

          // Avatar + Info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Stack(
                  children: [
                    GestureDetector(
                      onTap: _isOwner ? _alterarFoto : null,
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: _C.accent, width: 2.5),
                          color: _C.card,
                        ),
                        child: ClipOval(
                          child: fotoBytes != null
                              ? Image.memory(fotoBytes,
                                  fit: BoxFit.cover)
                              : const Icon(Icons.person_rounded,
                                  color: _C.grey3, size: 42),
                        ),
                      ),
                    ),
                    if (_uploadingPhoto)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x80000000),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: _C.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    if (_isOwner)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: _C.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: _C.white, size: 13),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 20),

                // Stats + bio
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats row
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _statItem(
                            _casosApoios.length.toString(),
                            'Apoios',
                          ),
                          _statItem(
                            _statAprovados.toString(),
                            'Aprovados',
                          ),
                          _statItem(
                            _statPendentes.toString(),
                            'Pendentes',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Edit button (só dono)
                      if (_isOwner)
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: OutlinedButton(
                            onPressed: _mostrarMenu,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: _C.border),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Editar Perfil',
                              style: TextStyle(
                                color: _C.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Nome + bio
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome com botão de editar (inline)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nome,
                        style: const TextStyle(
                          color: _C.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (_isOwner)
                      GestureDetector(
                        onTap: _editarNome,
                        child: const Icon(Icons.edit_rounded,
                            color: _C.grey3, size: 16),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.email_outlined,
                      size: 13, color: _C.grey3),
                  const SizedBox(width: 5),
                  Text(email,
                      style:
                          const TextStyle(color: _C.grey2, fontSize: 12)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 13, color: _C.grey3),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      local,
                      style: const TextStyle(
                          color: _C.grey2, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.visibility_outlined,
                      size: 13, color: _C.grey3),
                  const SizedBox(width: 5),
                  Text('$visitas visitas',
                      style: const TextStyle(
                          color: _C.grey2, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                // Apoios recebidos
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x26EF4444),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          size: 13, color: _C.red),
                      const SizedBox(width: 6),
                      Text(
                        'Os seus casos receberam $_statApoiosRecebidos apoios',
                        style: const TextStyle(
                          color: _C.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicador de localização
                if (_updatingLocation)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _C.accent,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'A detectar localização...',
                          style: TextStyle(
                              color: _C.accent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Emblemas
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                itemCount: badges.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final b = badges[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: b.bg,
                      borderRadius:
                          BorderRadius.circular(20),
                      border: Border.all(
                          color: b.color.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(b.icon,
                            size: 12, color: b.color),
                        const SizedBox(width: 5),
                        Text(
                          b.label,
                          style: TextStyle(
                            color: b.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _C.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: _C.grey3, fontSize: 11),
        ),
      ],
    );
  }

  // ── Grid de casos ────────────────────────────────────
  Widget _buildGrid(List<Map<String, dynamic>> lista,
      {required String tipo}) {
    if (lista.isEmpty) {
      final msg = tipo == 'apoios'
          ? 'Ainda não apoiou nenhum caso.'
          : 'Ainda não submeteu nenhum caso.';
      final icon = tipo == 'apoios'
          ? Icons.favorite_border_rounded
          : Icons.assignment_outlined;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _C.grey4, size: 52),
            const SizedBox(height: 12),
            Text(msg,
                style:
                    const TextStyle(color: _C.grey3, fontSize: 14)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final caso = lista[i];
        return _GridItem(caso: caso);
      },
    );
  }

  // ── Menu de opções ───────────────────────────────────
  void _mostrarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin:
                  const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: _C.grey4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('Opções',
                style: TextStyle(
                    color: _C.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: _C.orange),
              title: const Text('Editar Nome',
                  style: TextStyle(color: _C.white)),
              onTap: () {
                Navigator.pop(context);
                _editarNome();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: _C.accent),
              title: const Text('Alterar Foto de Perfil',
                  style: TextStyle(color: _C.white)),
              onTap: () {
                Navigator.pop(context);
                _alterarFoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: _C.green),
              title: const Text('Actualizar Localização',
                  style: TextStyle(color: _C.white)),
              onTap: () {
                Navigator.pop(context);
                _atualizarLocalizacaoAutomatica();
              },
            ),
            const Divider(color: _C.border),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: _C.red),
              title: const Text('Sair da Conta',
                  style: TextStyle(color: _C.red)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded,
                  color: _C.grey2),
              title: const Text('Cancelar',
                  style: TextStyle(color: _C.grey2)),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── ITEM DO GRID ───────────────────────────────────────
class _GridItem extends StatelessWidget {
  final Map<String, dynamic> caso;
  const _GridItem({required this.caso});

  @override
  Widget build(BuildContext context) {
    final imagem = caso['imagem'] as String? ?? '';
    final status = caso['status'] as String? ?? 'pendente';
    final apoios = caso['apoios'] as int? ?? 0;
    final coments = caso['comentarios'] as int? ?? 0;

    Uint8List? bytes;
    if (imagem.startsWith('data:image')) {
      try {
        bytes = base64Decode(imagem.split(',').last);
      } catch (_) {}
    }

    Color statusColor;
    switch (status) {
      case 'aprovado':
        statusColor = const Color(0xFF4F7EFF);
        break;
      case 'encontrado':
        statusColor = const Color(0xFF22C55E);
        break;
      case 'desmentido':
        statusColor = const Color(0xFF52525B);
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
    }

    return GestureDetector(
      onTap: () => _abrirLightbox(context, caso),
      child: Stack(
        fit: StackFit.expand,
        children: [
          bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover)
              : Container(
                  color: const Color(0xFF1C1C22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_rounded,
                          color: Color(0xFF3F3F46), size: 28),
                      const SizedBox(height: 4),
                      Text(
                        caso['nome'] as String? ?? '—',
                        style: const TextStyle(
                            color: Color(0xFF52525B),
                            fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xCC000000),
                    Colors.transparent
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded,
                      size: 10, color: Colors.white),
                  const SizedBox(width: 2),
                  Text('$apoios',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9)),
                  const SizedBox(width: 6),
                  const Icon(Icons.mode_comment_rounded,
                      size: 10, color: Colors.white),
                  const SizedBox(width: 2),
                  Text('$coments',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirLightbox(
      BuildContext context, Map<String, dynamic> caso) {
    final imagem = caso['imagem'] as String? ?? '';
    final status = caso['status'] as String? ?? 'pendente';
    final apoios = caso['apoios'] as int? ?? 0;
    final coments = caso['comentarios'] as int? ?? 0;
    final nome = caso['nome'] as String? ?? 'Sem nome';
    final userId = caso['userId'] as String?;

    Uint8List? bytes;
    if (imagem.startsWith('data:image')) {
      try {
        bytes = base64Decode(imagem.split(',').last);
      } catch (_) {}
    }

    final detalhes = [
      caso['idade'] != null ? '${caso['idade']} anos' : null,
      caso['sexo'] as String?,
      caso['municipio'] != null
          ? '📍 ${caso['municipio']}, ${caso['provincia'] ?? ''}'
          : null,
      caso['ultimo_local'] != null
          ? 'Último local: ${caso['ultimo_local']}'
          : null,
      caso['roupas'] != null
          ? 'Vestia: ${caso['roupas']}'
          : null,
      caso['informacoes_adicionais'] as String?,
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    Color statusColor;
    switch (status) {
      case 'aprovado':
        statusColor = const Color(0xFF4F7EFF);
        break;
      case 'encontrado':
        statusColor = const Color(0xFF22C55E);
        break;
      case 'desmentido':
        statusColor = const Color(0xFF52525B);
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C22),
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bytes != null
                  ? Image.memory(
                      bytes,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 180,
                      color: const Color(0xFF141418),
                      child: const Icon(
                          Icons.person_rounded,
                          size: 64,
                          color: Color(0xFF3F3F46)),
                    ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              statusColor.withOpacity(0.2),
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor
                                .withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ]),
                    if (detalhes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        detalhes,
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.favorite_rounded,
                          size: 14, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Text('$apoios apoios',
                          style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 12)),
                      const SizedBox(width: 16),
                      const Icon(Icons.mode_comment_rounded,
                          size: 14, color: Color(0xFF4F7EFF)),
                      const SizedBox(width: 4),
                      Text('$coments comentários',
                          style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    // Botão para ver perfil do autor
                    if (userId != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfileScreen(
                                        targetUid:
                                            userId),
                              ),
                            );
                          },
                          icon: const Icon(
                              Icons.person_rounded,
                              size: 16),
                          label: const Text(
                              'Ver perfil do autor'),
                          style:
                              OutlinedButton.styleFrom(
                            foregroundColor:
                                const Color(0xFF4F7EFF),
                            side: const BorderSide(
                                color:
                                    Color(0xFF4F7EFF)),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                      8),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            Navigator.pop(context),
                        child: const Text('Fechar',
                            style: TextStyle(
                                color:
                                    Color(0xFF4F7EFF))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}