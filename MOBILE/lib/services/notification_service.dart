// services/notification_service.dart
// Envia notificacoes reais via FCM HTTP v1 API com autenticacao JWT

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.showAmberAlert(
    title:   message.notification?.title ?? 'Alerta de Desaparecimento',
    body:    message.notification?.body  ?? '',
    payload: message.data,
  );
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'amber_alert_channel';
  static const _channelName = 'Alertas de Desaparecimento';
  static const _channelDesc = 'Notificacoes urgentes de pessoas desaparecidas';
  static const _projectId   = 'missingao-88704';

  // ── Inicializar ───────────────────────────────────────
  Future<void> init() async {
    await _fcm.requestPermission(
      alert: true, badge: true, sound: true, criticalAlert: true,
    );

    final androidChannel = AndroidNotificationChannel(
      _channelId, _channelName,
      description:      _channelDesc,
      importance:       Importance.max,
      playSound:        true,
      enableVibration:  true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      ledColor:         const Color(0xFFFF6B00),
      enableLights:     true,
    );

    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _local.initialize(initSettings);

    _fcm.onTokenRefresh.listen(_guardarTokenFirestore);

    FirebaseMessaging.onMessage.listen((msg) {
      showAmberAlert(
        title:   msg.notification?.title ?? 'Alerta de Desaparecimento',
        body:    msg.notification?.body  ?? '',
        payload: msg.data,
      );
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // ── Guardar token após login ──────────────────────────
  Future<void> salvarTokenAposLogin() async {
    await _salvarToken();
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
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true)); // ← merge:true cria ou actualiza
    } catch (e) {
      debugPrint('Erro ao guardar token: $e');
    }
  }


  // ── Gerar token de acesso OAuth2 via JWT ─────────────
  Future<String?> _getAccessToken() async {
    try {
      final now = DateTime.now();
      final expiry = now.add(const Duration(hours: 1));

      final jwt = JWT(
        {
          'iss': fcmClientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': expiry.millisecondsSinceEpoch ~/ 1000,
        },
      );

      final token = jwt.sign(
        RSAPrivateKey(fcmPrivateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      // Trocar JWT por access token OAuth2
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion':  token,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['access_token'] as String?;
      } else {
        debugPrint('Erro ao obter access token: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Erro ao gerar JWT: $e');
      return null;
    }
  }

  // ── Enviar notificacao FCM para um token especifico ───
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
          'notification': {
            'title': title,
            'body':  body,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id':  _channelId,
              'priority':    'max',
              'visibility':  'public',
              'default_vibrate_timings': false,
              'vibrate_timings': ['0s', '0.5s', '0.2s', '0.5s'],
              'color': '#FF6B00',
              'sound': 'default',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound':             'default',
                'badge':             1,
                'interruption-level': 'critical',
              },
            },
          },
          if (data != null) 'data': data,
        },
      };

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('Notificacao enviada com sucesso para: $token');
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

  // ── Mostrar notificacao local estilo Amber Alert ──────
  Future<void> showAmberAlert({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
    Uint8List? imagemBytes,
  }) async {
    final BigPictureStyleInformation? bigPicture = imagemBytes != null
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
      _channelId, _channelName,
      channelDescription:  _channelDesc,
      importance:          Importance.max,
      priority:            Priority.max,
      styleInformation:    bigPicture ?? bigText,
      color:               const Color(0xFFFF6B00),
      colorized:           true,
      ticker:              'Alerta de Desaparecimento',
      fullScreenIntent:    true,
      category:            AndroidNotificationCategory.alarm,
      visibility:          NotificationVisibility.public,
      playSound:           true,
      enableVibration:     true,
      vibrationPattern:    Int64List.fromList([0, 500, 200, 500, 200, 500]),
      enableLights:        true,
      ledColor:            const Color(0xFFFF6B00),
      ledOnMs:             1000,
      ledOffMs:            500,
      ongoing:             false,
      autoCancel:          true,
      largeIcon:           imagemBytes != null ? ByteArrayAndroidBitmap(imagemBytes) : null,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true, presentBadge: true, presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload != null ? jsonEncode(payload) : null,
    );
  }

  // ── Enviar alerta a utilizadores de Luanda ────────────
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
    String? imagemBase64,
  }) async {
    try {
      // Buscar tokens FCM dos utilizadores
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('fcmToken', isNotEqualTo: null)
          .get();

      final tokens = <String>[];
      for (final doc in usersSnap.docs) {
        final data  = doc.data();
        final token = data['fcmToken'] as String?;
        if (token == null || token.isEmpty) continue;

        final userProv = (data['provincia'] as String? ?? '').toLowerCase();
        // Notificar utilizadores de Luanda ou sem provincia definida
        if (userProv.isEmpty || userProv == 'luanda' || provincia.toLowerCase() == 'luanda') {
          tokens.add(token);
        }
      }

      debugPrint('Tokens encontrados: ${tokens.length}');

      if (tokens.isEmpty) {
        debugPrint('Nenhum token FCM encontrado.');
        return;
      }

      final title = 'ALERTA — $nome desapareceu!';
      final body = [
        '📍 $ultimoLocal',
        if (idade.isNotEmpty) '$idade anos',
        if (sexo.isNotEmpty) sexo,
        if (roupas.isNotEmpty) 'Vestia: $roupas',
        if (informacoes.isNotEmpty) informacoes,
      ].join(' · ');

      final data = {
        'casoId': casoId,
        'tipo':   'alerta_desaparecido',
        'nome':   nome,
      };

      // Enviar para cada token via FCM HTTP v1
      int enviados = 0;
      for (final token in tokens) {
        final ok = await _enviarFCM(
          token: token,
          title: title,
          body:  body,
          data:  data,
        );
        if (ok) enviados++;
      }

      // Guardar registo no Firestore
      await FirebaseFirestore.instance.collection('alertas').add({
        'casoId':         casoId,
        'nome':           nome,
        'provincia':      provincia,
        'municipio':      municipio,
        'ultimoLocal':    ultimoLocal,
        'idade':          idade,
        'sexo':           sexo,
        'criadoEm':       Timestamp.now(),
        'tokensEnviados': enviados,
      });

      // Mostrar tambem notificacao local no admin
      Uint8List? imgBytes;
      if (imagemBase64 != null && imagemBase64.contains(',')) {
        try { imgBytes = base64Decode(imagemBase64.split(',').last); } catch (_) {}
      }

      await showAmberAlert(
        title:       title,
        body:        body,
        imagemBytes: imgBytes,
        payload:     {'casoId': casoId, 'tipo': 'alerta_desaparecido'},
      );

      debugPrint('Alerta enviado para $enviados/${tokens.length} dispositivos.');
    } catch (e) {
      debugPrint('Erro ao enviar alerta: $e');
    }
  }
}