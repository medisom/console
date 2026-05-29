import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/app_identity.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class VerifyCodeExtra {
  final String email;
  final String userId;
  final String deviceId;

  const VerifyCodeExtra({required this.email, required this.userId, required this.deviceId});
}

class VerifyCodePage extends StatefulWidget {
  final Object? extra;

  const VerifyCodePage({super.key, required this.extra});

  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  final _code = TextEditingController();
  bool _loading = false;

  String? _serverMessage;
  bool _verified = false;

  VerifyCodeExtra? get _extra {
    final e = widget.extra;
    if (e is VerifyCodeExtra) return e;
    if (e is Map) {
      try {
        final email = (e['email'] ?? e['e_mail'] ?? '').toString();
        final userId = (e['user_id'] ?? '').toString();
        final deviceId = (e['device_id'] ?? '').toString();
        if (email.isNotEmpty) return VerifyCodeExtra(email: email, userId: userId, deviceId: deviceId);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _decodeResponseBody(http.Response resp) {
    try {
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('validate-verification-code decode failed: $e');
      return resp.body;
    }
  }

  String? _tryParseApiMessage(String body) {
    try {
      var sanitized = body.trim();
      if (sanitized.startsWith('\ufeff')) sanitized = sanitized.substring(1).trimLeft();
      if (!sanitized.startsWith('{') && !sanitized.startsWith('[')) {
        final objIdx = sanitized.indexOf('{');
        final arrIdx = sanitized.indexOf('[');
        final idx = (objIdx == -1)
            ? arrIdx
            : (arrIdx == -1)
                ? objIdx
                : (objIdx < arrIdx ? objIdx : arrIdx);
        if (idx > 0) sanitized = sanitized.substring(idx);
      }

      final decoded = jsonDecode(sanitized);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'] ?? decoded['mensagem'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Map<String, dynamic>? _tryParseApiMap(String body) {
    try {
      var sanitized = body.trim();
      if (sanitized.startsWith('\ufeff')) sanitized = sanitized.substring(1).trimLeft();
      if (!sanitized.startsWith('{') && !sanitized.startsWith('[')) {
        final objIdx = sanitized.indexOf('{');
        final arrIdx = sanitized.indexOf('[');
        final idx = (objIdx == -1)
            ? arrIdx
            : (arrIdx == -1)
                ? objIdx
                : (objIdx < arrIdx ? objIdx : arrIdx);
        if (idx > 0) sanitized = sanitized.substring(idx);
      }
      final decoded = jsonDecode(sanitized);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _validateCode() async {
    final extra = _extra;
    if (extra == null) {
      debugPrint('VerifyCodePage: missing navigation extra (email/user_id/device_id).');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão de verificação expirada. Volte e solicite o código novamente.'),
        ),
      );
      return;
    }

    final email = extra.email.trim();
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _serverMessage = 'Digite os 6 dígitos do código.');
      return;
    }

    setState(() {
      _loading = true;
      _serverMessage = null;
    });

    try {
      final deviceId = extra.deviceId.isNotEmpty ? extra.deviceId : await AppIdentity.getOrCreateDeviceId();
      final userId = extra.userId.isNotEmpty ? extra.userId : await AppIdentity.getOrCreateUserId();

      final payload = <String, dynamic>{
        'user_id': userId,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
        'e_mail': email,
        'verification_code': code,
        'app_version': AppIdentity.appVersion,
      };

      final uri = Uri.https('medisom.com.br', '/iot/app/validate-verification-code');
      final resp = await http
          .post(
            uri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(payload),
            encoding: utf8,
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      final bodyText = _decodeResponseBody(resp);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = _tryParseApiMap(bodyText);
        final apiMsg = decoded != null ? (decoded['message'] ?? decoded['mensagem'])?.toString() : _tryParseApiMessage(bodyText);

        setState(() {
          _serverMessage = (apiMsg != null && apiMsg.trim().isNotEmpty) ? apiMsg.trim() : 'Código validado.';
          _verified = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_serverMessage!)));

        // Se o backend habilitar o usuário para login, seguir para criação de senha.
        // O backend pode retornar user_id/device_id/e_mail.
        if (decoded != null) {
          final userId = (decoded['user_id'] ?? '').toString();
          final deviceId = (decoded['device_id'] ?? '').toString();
          final eMail = (decoded['e_mail'] ?? decoded['email'] ?? decoded['e-mail'] ?? email).toString();

          // Navega para configurar senha sempre que vier success=true.
          // (Caso futuramente o backend retorne um flag para pular, ajustamos aqui.)
          if ((decoded['success'] == true || decoded['success']?.toString() == 'true') && userId.isNotEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (!mounted) return;
            final loc = Uri(
              path: AppRoutes.setPassword,
              queryParameters: {
                'user_id': userId,
                if (deviceId.isNotEmpty) 'device_id': deviceId,
                'e_mail': eMail,
              },
            ).toString();
            context.go(loc, extra: {
              'user_id': userId,
              'device_id': deviceId,
              'e_mail': eMail,
            });
          }
        }
      } else {
        debugPrint('validate-verification-code failed: ${resp.statusCode} $bodyText');
        final apiMsg = _tryParseApiMessage(bodyText);
        final msg = apiMsg ?? 'Não foi possível validar o código. (${resp.statusCode})';
        setState(() {
          _serverMessage = msg;
          _verified = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on TimeoutException catch (e) {
      debugPrint('validate-verification-code timeout: $e');
      if (!mounted) return;
      setState(() {
        _serverMessage = 'Tempo esgotado ao validar o código. Tente novamente.';
        _verified = false;
      });
    } on http.ClientException catch (e) {
      debugPrint('validate-verification-code client exception: $e');
      if (!mounted) return;

      final msg = e.toString();
      final isDns = msg.contains('Failed host lookup') || msg.contains('No address associated with hostname');
      final isCorsOrWebBlocked = kIsWeb && (msg.contains('XMLHttpRequest') || msg.contains('CORS') || msg.contains('Origin'));
      setState(() {
        _serverMessage = isDns
            ? 'Sem acesso ao servidor (falha de DNS).'
            : isCorsOrWebBlocked
                ? 'No navegador, a chamada pode estar bloqueada (CORS).'
                : 'Falha de conexão com o servidor.';
        _verified = false;
      });
    } catch (e) {
      debugPrint('validate-verification-code unexpected error: $e');
      if (!mounted) return;
      setState(() {
        _serverMessage = 'Erro ao validar o código. Tente novamente.';
        _verified = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openHelpSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: cs.surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: Icon(Icons.arrow_back, color: cs.onSurface),
                      tooltip: 'Voltar',
                    ),
                    Expanded(
                      child: Text('Não recebeu um código?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se você não recebeu o código de verificação, verifique se:',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.25),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _HelpItem(index: 1, text: 'O endereço de e-mail está certo.'),
                    _HelpItem(index: 2, text: 'O e-mail não está na pasta de lixo eletrônico.'),
                    _HelpItem(
                      index: 3,
                      text:
                          'Se você não conseguir encontrar o e-mail, ele pode estar bloqueado pelo seu firewall. Use um servidor de e-mail com melhor compatibilidade.',
                    ),
                    _HelpItem(
                      index: 4,
                      text:
                          'Se mesmo assim você não conseguir obter o código, fale com o atendimento ao cliente e informe o nome da sua conta e o horário específico da ocorrência.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final extra = _extra;
    final email = extra?.email ?? '';

    return ResponsiveAuthScaffold(
      title: 'Verificar e-mail',
      subtitle: 'Digite o código enviado para confirmar seu cadastro.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.register);
                  }
                },
                icon: Icon(Icons.arrow_back, color: cs.onSurface),
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Código de autenticação', style: context.textStyles.titleLarge)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'O código de verificação foi enviado para seu endereço de e-mail: $email',
            style: context.textStyles.bodyMedium?.copyWith(height: 1.35, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            onSubmitted: (_) => _loading ? null : _validateCode(),
            decoration: const InputDecoration(
              labelText: 'Código (6 dígitos)',
              prefixIcon: Icon(Icons.verified_outlined),
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            onPressed: _loading ? null : _validateCode,
            label: 'Validar código',
            icon: Icons.check_circle_outline,
            isLoading: _loading,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openHelpSheet,
              child: const Text('Não recebeu um código?'),
            ),
          ),
          if (_serverMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text(
                _serverMessage!,
                style: context.textStyles.bodyMedium?.copyWith(height: 1.35, color: cs.onSurface),
              ),
            ),
          ],
          if (_verified) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.login),
              icon: const Icon(Icons.login),
              label: const Text('Ir para login'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final int index;
  final String text;

  const _HelpItem({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$index.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface, height: 1.35)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurface, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
