// services/notification_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../config.dart';

// ── Handler de notificação em background (top-level obrigatório) ────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.showAmberAlert(
    title:   message.notification?.title ?? 'Alerta de Desaparecimento',
    body:    message.notification?.body  ?? '',
    payload: message.data,
  );
}

// ── Handler de toque em notificação local em background (top-level) ─────────
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.payload != null) {
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      NotificationService.instance.handleNotificationNavigation(data);
    } catch (_) {}
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();


  static const _channelId   = 'amber_alert_channel_v2';
  static const _channelName = 'Alertas de Desaparecimento';
  static const _channelDesc = 'Notificações urgentes de pessoas desaparecidas';
  static const _projectId   = 'missingao-88704';


  static final navigatorKey = GlobalKey<NavigatorState>();

  // ── Inicializar ───────────────────────────────────────────────────────────
  Future<void> init() async {
    await _fcm.requestPermission(
      alert: true, badge: true, sound: true, criticalAlert: true,
    );

    // Canal Android com som personalizado amber_alert
    // (o ficheiro tem de existir em android/app/src/main/res/raw/)
    final androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description:      _channelDesc,
      importance:       Importance.max,
      playSound:        true,
      // ── Som de amber alert ───────────────────────────────────────────────
      // Requer: android/app/src/main/res/raw/amber_alert.mp3
      sound:            const RawResourceAndroidNotificationSound('amber_alert'),
      enableVibration:  true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500, 200, 500]),
      ledColor:         const Color(0xFFFF6B00),
      enableLights:     true,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission:    true,
        requestBadgePermission:    true,
        requestSoundPermission:    true,
        requestCriticalPermission: true, // iOS Critical Alerts
      ),
    );

    await _local.initialize(
      initSettings,
      // ── Toque na notificação local (app em foreground ou background) ─────
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            handleNotificationNavigation(data);
          } catch (_) {}
        }
      },
      // ── Toque em notificação local quando a app estava terminada ─────────
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _fcm.onTokenRefresh.listen(_guardarTokenFirestore);

    // Notificação recebida em foreground → mostra alerta local
    FirebaseMessaging.onMessage.listen((msg) {
      showAmberAlert(
        title:   msg.notification?.title ?? 'Alerta de Desaparecimento',
        body:    msg.notification?.body  ?? '',
        payload: msg.data,
      );
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // ── Navegar ao tocar na notificação ─────────────────────────────────────
  // Abre a HomePage (feed) e logo a seguir o MapPage (localização no mapa)
  void handleNotificationNavigation(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    debugPrint('🔔 Notificação tocada — payload: $data');

    // Remove todos os ecrãs anteriores e abre o feed
    nav.pushNamedAndRemoveUntil('/home', (_) => false);

    // Após um frame, abre o mapa por cima do feed
    // (o utilizador pode carregar "voltar" para ver o feed)
    Future.delayed(const Duration(milliseconds: 250), () {
      navigatorKey.currentState?.pushNamed('/map');
    });
  }

  // ── Guardar token + localização após login ───────────────────────────────
  Future<void> salvarTokenAposLogin() async {
    await _salvarToken();
    await _salvarLocalizacao();
  }

  Future<void> _salvarToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      await _guardarTokenFirestore(token);
      debugPrint('FCM Token guardado: $token');
    } catch (e) {
      debugPrint('Erro ao guardar token: $e');
    }
  }

  Future<void> _guardarTokenFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao guardar token: $e');
    }
  }

  // ── Guardar localização GPS actual ───────────────────────────────────────
  Future<void> _salvarLocalizacao() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      String municipioActual = '';
      String provinciaActual = '';

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          municipioActual = place.subAdministrativeArea ?? place.locality ?? '';
          provinciaActual = place.administrativeArea ?? '';
        }
      } catch (_) {}

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'localizacaoActual': {
          'lat':       position.latitude,
          'lng':       position.longitude,
          'municipio': municipioActual.toLowerCase(),
          'provincia': provinciaActual.toLowerCase(),
          'timestamp': Timestamp.now(),
        },
      }, SetOptions(merge: true));

      debugPrint('Localização guardada: $municipioActual, $provinciaActual');
    } catch (e) {
      debugPrint('Erro ao obter localização: $e');
    }
  }

  // ── Gerar token OAuth2 via JWT ───────────────────────────────────────────
  Future<String?> _getAccessToken() async {
    try {
      final now    = DateTime.now();
      final expiry = now.add(const Duration(hours: 1));

      final jwt = JWT({
        'iss':   fcmClientEmail,
        'scope': 'https://www.googleapis.com/auth/firebase.messaging',
        'aud':   'https://oauth2.googleapis.com/token',
        'iat':   now.millisecondsSinceEpoch ~/ 1000,
        'exp':   expiry.millisecondsSinceEpoch ~/ 1000,
      });

      final token = jwt.sign(RSAPrivateKey(fcmPrivateKey), algorithm: JWTAlgorithm.RS256);

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion':  token,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['access_token'] as String?;
      } else {
        debugPrint('Erro access token: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Erro JWT: $e');
      return null;
    }
  }

  // ── Enviar FCM para um token ─────────────────────────────────────────────
  Future<bool> _enviarFCM({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) return false;

      final payload = {
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id':              _channelId,
              'visibility':              'public',
              'default_vibrate_timings': false,
              'vibrate_timings':         ['0s', '0.5s', '0.2s', '0.5s', '0.2s', '0.5s'],
              // Som amber_alert (requer o ficheiro no projeto Android)
              'sound':                   'amber_alert',
              'color':                   '#FF6B00',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                // Requer entitlement Apple para Critical Alerts
                'sound':              'amber_alert.aiff',
                'badge':              1,
                'interruption-level': 'critical',
              },
            },
          },
          if (data != null) 'data': data,
        },
      };

      final response = await http.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('Notificação enviada: $token');
        return true;
      } else {
        debugPrint('Erro FCM: ${response.statusCode} — ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Erro ao enviar FCM: $e');
      return false;
    }
  }

  // ── Mostrar notificação local Amber Alert ────────────────────────────────
  Future<void> showAmberAlert({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
    Uint8List? imagemBytes,
  }) async {
    final bigPicture = imagemBytes != null
        ? BigPictureStyleInformation(
            ByteArrayAndroidBitmap(imagemBytes),
            largeIcon:              ByteArrayAndroidBitmap(imagemBytes),
            contentTitle:           title,
            summaryText:            body,
            htmlFormatContentTitle: true,
            htmlFormatSummaryText:  true,
          )
        : null;

    final bigText = BigTextStyleInformation(
      body,
      htmlFormatBigText:      true,
      contentTitle:           title,
      htmlFormatContentTitle: true,
    );

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:  _channelDesc,
      importance:          Importance.max,
      priority:            Priority.max,
      styleInformation:    bigPicture ?? bigText,
      color:               const Color(0xFFFF6B00),
      colorized:           true,
      ticker:              '⚠️ Alerta de Desaparecimento',
      // ── Amber Alert: full-screen mesmo com o telemóvel bloqueado ────────
      fullScreenIntent:    true,
      category:            AndroidNotificationCategory.alarm,
      visibility:          NotificationVisibility.public,
      playSound:           true,
      // Som personalizado (requer android/app/src/main/res/raw/amber_alert.mp3)
      sound:               const RawResourceAndroidNotificationSound('amber_alert'),
      enableVibration:     true,
      // Padrão de vibração agressivo: 0ms pausa, 500ms vib, 200ms pausa... (×4)
      vibrationPattern:    Int64List.fromList([0, 500, 200, 500, 200, 500, 200, 500]),
      enableLights:        true,
      ledColor:            const Color(0xFFFF6B00),
      ledOnMs:             500,
      ledOffMs:            200,
      ongoing:             false,
      autoCancel:          true,
      largeIcon: imagemBytes != null
          ? ByteArrayAndroidBitmap(imagemBytes)
          : null,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert:      true,
      presentBadge:      true,
      presentSound:      true,
      // Som personalizado iOS (requer ios/Runner/amber_alert.aiff)
      sound:             'amber_alert.aiff',
      // Critical Alert: toca mesmo em modo silencioso / Não Incomodar
      // (requer entitlement da Apple — funciona sem ele mas ignora o DnD)
      interruptionLevel: InterruptionLevel.critical,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload != null ? jsonEncode(payload) : null,
    );
  }

  // ── Enviar email via EmailJS ─────────────────────────────────────────────
  Future<void> _enviarEmailAlerta({
    required String nome,
    required String provincia,
    required String municipio,
    required String ultimoLocal,
    required String idade,
    required String sexo,
    required String roupas,
    required String informacoes,
    required String casoId,
  }) async {
    try {
      debugPrint('📧 [EMAIL] Iniciando envio via EmailJS...');

      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .get(const GetOptions(source: Source.server));

      final emails = <String>[];
      for (final doc in usersSnap.docs) {
        final email = doc.data()['email'] as String?;
        if (email != null && email.trim().isNotEmpty) {
          emails.add(email.trim());
        }
      }

      debugPrint('📧 [EMAIL] Emails encontrados: ${emails.length}');
      if (emails.isEmpty) return;

      final templateParams = {
        'bcc_emails':        emails.join(','),
        'nome_desaparecido': nome,
        'idade':             idade,
        'local': '$ultimoLocal${municipio.isNotEmpty ? ' - $municipio' : ''}',
        'data':  DateTime.now().toIso8601String().substring(0, 10),
        'roupas':    roupas.isNotEmpty ? roupas : 'Não informado',
        'info':      informacoes.isNotEmpty ? informacoes : 'Sem informações adicionais.',
      };

      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin':       'http://localhost',
        },
        body: jsonEncode({
          'service_id':      'service_8fq9usa',
          'template_id':     'template_366wv9e',
          'user_id':         'R5Femg5uCIC-Lh0RW',
          'template_params': templateParams,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📧 [EMAIL] ✅ Enviado para ${emails.length} destinatários.');
      } else {
        debugPrint('📧 [EMAIL] ❌ Erro: ${response.statusCode} — ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('📧 [EMAIL] ❌ ERRO: $e\n$stack');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NOVO: notificação de estado de conta (suspensão / reactivação)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Chamada pelo TrustService sempre que uma conta transita para suspensa
  // ou é reactivada. Usa DOIS canais em paralelo, porque servem propósitos
  // diferentes:
  //   • Push (FCM) — imediato, mas só chega se a app estiver instalada e o
  //     dispositivo tiver o token guardado (não existe na versão web).
  //   • Email (EmailJS) — mais lento a ser visto, mas chega a QUALQUER
  //     utilizador com email registado, incluindo a versão web da app, que
  //     por agora só recebe notificações por este canal.
  //
  // Falhas num canal não bloqueiam o outro nem a operação de suspender/
  // reactivar em si — por isso todo o corpo está dentro de um único
  // try/catch que só regista o erro (debugPrint), nunca o propaga.
  Future<void> notificarSuspensao({
    required String uid,
    required String motivo,
  }) => _notificarEstadoConta(uid: uid, suspenso: true, motivo: motivo);

  Future<void> notificarReactivacao({
    required String uid,
    required int score,
  }) => _notificarEstadoConta(uid: uid, suspenso: false, score: score);

  Future<void> _notificarEstadoConta({
    required String uid,
    required bool suspenso,
    String? motivo,
    int? score,
  }) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userDoc.exists) return;
      final data  = userDoc.data()!;
      final nome  = data['nome']     as String? ?? 'Utilizador';
      final email = data['email']    as String?;
      final token = data['fcmToken'] as String?;

      final titulo = suspenso ? '🚫 Conta Suspensa' : '✅ Conta Reactivada';
      final corpo = suspenso
          ? 'A sua conta foi suspensa. Motivo: ${motivo ?? "violação das diretrizes"}. Pode falar com o suporte a partir da app para pedir revisão.'
          : 'A sua conta foi reactivada com $score pontos de Trust Score. Já pode voltar a usar a plataforma normalmente.';

      // Canal 1 — push, só se houver token guardado (app móvel)
      if (token != null && token.isNotEmpty) {
        await _enviarFCM(
          token: token,
          title: titulo,
          body:  corpo,
          data:  {'tipo': 'status_conta', 'estado': suspenso ? 'suspensa' : 'reactivada'},
        );
      }

      // Canal 2 — email, chega também à versão web (que ainda não tem push)
      if (email != null && email.isNotEmpty) {
        await _enviarEmailEstadoConta(email: email, nome: nome, assunto: titulo, mensagem: corpo);
      }
    } catch (e) {
      debugPrint('Erro ao notificar estado da conta: $e');
    }
  }

  // IMPORTANTE: 'template_conta_status' é um ID placeholder — é preciso
  // criar este template no painel do EmailJS (o mesmo projecto onde já
  // existe o 'template_366wv9e') antes disto funcionar. Configuração
  // mínima sugerida para o template:
  //   • Campo "To Email" do template → {{to_email}}
  //   • Assunto do template → {{assunto}}
  //   • Corpo do template → algo como:
  //       "Olá {{nome}},\n\n{{mensagem}}\n\n— Equipa Missing AO"
  // Depois de criado, substituir o ID abaixo pelo ID real gerado pelo EmailJS.
  Future<void> _enviarEmailEstadoConta({
    required String email,
    required String nome,
    required String assunto,
    required String mensagem,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin':       'http://localhost',
        },
        body: jsonEncode({
          'service_id':      'service_8fq9usa',
          'template_id':     'template_conta_status', // ← substituir pelo ID real
          'user_id':         'R5Femg5uCIC-Lh0RW',
          'template_params': {
            'to_email': email,
            'nome':     nome,
            'assunto':  assunto,
            'mensagem': mensagem,
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('📧 [ESTADO CONTA] ✅ Enviado a $email');
      } else {
        debugPrint('📧 [ESTADO CONTA] ❌ Erro: ${response.statusCode} — ${response.body}');
      }
    } catch (e) {
      debugPrint('📧 [ESTADO CONTA] ❌ Erro de ligação: $e');
    }
  }

  // ── Enviar alerta por município ──────────────────────────────────────────
  Future<void> enviarAlertaDesaparecido({
    required String nome,
    required String provincia,
    required String municipio,
    required String ultimoLocal,
    required String idade,
    required String sexo,
    required String roupas,
    required String informacoes,
    required String casoId,
    required String autorUserId,
    String? imagemBase64,
  }) async {
    try {
      final municipioAlvo = municipio.toLowerCase().trim();
      final provinciaAlvo = provincia.toLowerCase().trim();

      debugPrint('Enviando alerta — município: $municipioAlvo, autor: $autorUserId');

      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('fcmToken', isNotEqualTo: null)
          .get();

      final tokensSet = <String>{};

      for (final doc in usersSnap.docs) {
        final data  = doc.data();
        final token = data['fcmToken'] as String?;
        if (token == null || token.isEmpty) continue;

        final uid = doc.id;

        if (uid == autorUserId) {
          tokensSet.add(token);
          continue;
        }

        bool deveNotificar = false;
        final locActual = data['localizacaoActual'] as Map<String, dynamic>?;

        if (locActual != null) {
          final userMunicipio =
              (locActual['municipio'] as String? ?? '').toLowerCase().trim();
          final userProvincia =
              (locActual['provincia'] as String? ?? '').toLowerCase().trim();

          if (municipioAlvo.isNotEmpty && userMunicipio.isNotEmpty) {
            deveNotificar = userMunicipio.contains(municipioAlvo) ||
                municipioAlvo.contains(userMunicipio);
          } else if (provinciaAlvo.isNotEmpty && userProvincia.isNotEmpty) {
            deveNotificar = userProvincia.contains(provinciaAlvo) ||
                provinciaAlvo.contains(userProvincia);
          }
        } else {
          final userMunicipio =
              (data['municipio'] as String? ?? '').toLowerCase().trim();
          final userProvincia =
              (data['provincia'] as String? ?? '').toLowerCase().trim();

          if (municipioAlvo.isNotEmpty && userMunicipio.isNotEmpty) {
            deveNotificar = userMunicipio.contains(municipioAlvo) ||
                municipioAlvo.contains(userMunicipio);
          } else if (provinciaAlvo.isNotEmpty && userProvincia.isNotEmpty) {
            deveNotificar = userProvincia.contains(provinciaAlvo) ||
                provinciaAlvo.contains(userProvincia);
          } else {
            deveNotificar = true;
          }
        }

        if (deveNotificar) tokensSet.add(token);
      }

      final tokens = tokensSet.toList();
      debugPrint('Total tokens para notificar: ${tokens.length}');

      final title = '⚠️ ALERTA — $nome desapareceu!';
      final body = [
        '📍 $ultimoLocal',
        if (municipio.isNotEmpty) '🏙️ $municipio, $provincia',
        if (idade.isNotEmpty) '$idade anos',
        if (sexo.isNotEmpty) sexo,
        if (roupas.isNotEmpty) 'Vestia: $roupas',
        if (informacoes.isNotEmpty) informacoes,
      ].join(' · ');

      final dataPayload = {
        'casoId':    casoId,
        'tipo':      'alerta_desaparecido',
        'nome':      nome,
        'municipio': municipio,
      };

      // Envia push para todos os dispositivos elegíveis
      int enviados = 0;
      for (final token in tokens) {
        final ok = await _enviarFCM(
          token: token,
          title: title,
          body:  body,
          data:  dataPayload,
        );
        if (ok) enviados++;
      }

      // Envia email via EmailJS
      await _enviarEmailAlerta(
        nome: nome, provincia: provincia, municipio: municipio,
        ultimoLocal: ultimoLocal, idade: idade, sexo: sexo,
        roupas: roupas, informacoes: informacoes, casoId: casoId,
      );

      // Guarda histórico no Firestore
      await FirebaseFirestore.instance.collection('alertas').add({
        'casoId':         casoId,
        'nome':           nome,
        'provincia':      provincia,
        'municipio':      municipio,
        'ultimoLocal':    ultimoLocal,
        'autorUserId':    autorUserId,
        'criadoEm':       Timestamp.now(),
        'tokensEnviados': enviados,
      });

      // Mostra alerta local no dispositivo do admin que aprovou
      Uint8List? imgBytes;
      if (imagemBase64 != null && imagemBase64.contains(',')) {
        try {
          imgBytes = base64Decode(imagemBase64.split(',').last);
        } catch (_) {}
      }

      await showAmberAlert(
        title:       title,
        body:        body,
        imagemBytes: imgBytes,
        payload:     {'casoId': casoId, 'tipo': 'alerta_desaparecido'},
      );

      debugPrint('✅ Alerta enviado para $enviados/${tokens.length} dispositivos.');
    } catch (e, stack) {
      debugPrint('Erro ao enviar alerta: $e\n$stack');
    }
  }
}
