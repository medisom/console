import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:medisom_console/nav.dart';
import 'package:medisom_console/theme.dart';
import 'package:medisom_console/utils/app_identity.dart';
import 'package:medisom_console/pages/verify_code_page.dart';
import 'package:medisom_console/widgets/primary_button.dart';
import 'package:medisom_console/widgets/responsive_auth_scaffold.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _email = TextEditingController();
  bool _loading = false;

  Future<void> _showExistingAccountDialog({required String email}) async {
    final cs = Theme.of(context).colorScheme;
    // Capture router from the page context (not the dialog context) so we can
    // navigate reliably after closing the dialog.
    final router = GoRouter.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Esta conta já existe. Gostaria de entrar?', style: context.textStyles.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.65)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                            ),
                            child: Text('Cancelar', style: TextStyle(color: cs.onSurface)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              router.pop();
                              final target = Uri(path: AppRoutes.login, queryParameters: {'email': email}).toString();
                              router.go(target);
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                            child: const Text('Entrar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _decodeResponseBody(http.Response resp) {
    // http.Response.body pode cair em latin1 quando o servidor não informa charset.
    // Como o backend pode retornar acentos (ex.: "E-mail inválido."), preferimos
    // sempre decodificar a partir de bytes em UTF-8.
    try {
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('Failed to decode response body as utf8: $e');
      return resp.body;
    }
  }

  String? _tryParseApiMessage(String body) {
    try {
      var sanitized = body;
      // Alguns backends/proxies podem devolver BOM UTF-8, whitespace extra, ou
      // até algum prefixo antes do JSON; isso faz o jsonDecode falhar.
      sanitized = sanitized.trim();
      if (sanitized.startsWith('\ufeff')) sanitized = sanitized.substring(1).trimLeft();

      // Se ainda assim não começar com um JSON, tentamos recortar do primeiro '{'/'['.
      if (!sanitized.startsWith('{') && !sanitized.startsWith('[')) {
        final objIdx = sanitized.indexOf('{');
        final arrIdx = sanitized.indexOf('[');
        final idx = (objIdx == -1)
            ? arrIdx
            : (arrIdx == -1)
                ? objIdx
                : min(objIdx, arrIdx);
        if (idx > 0) sanitized = sanitized.substring(idx);
      }

      final decoded = jsonDecode(sanitized);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'] ?? decoded['mensagem'];
        if (msg is String && msg.trim().isNotEmpty) return msg.trim();

        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final nestedMsg = error['message'] ?? error['mensagem'];
          if (nestedMsg is String && nestedMsg.trim().isNotEmpty) return nestedMsg.trim();
        }
      }
    } catch (_) {
      // ignore: no-op
    }
    return null;
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _requestVerificationCode() async {
    final email = _email.text.trim();
    // Conforme solicitado: sem validação completa de e-mail.
    // Apenas exigimos que tenha pelo menos um "@" antes de liberar a chamada.
    if (!email.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite pelo menos um "@" no e-mail para solicitar o código.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final deviceId = await AppIdentity.getOrCreateDeviceId();
      final userId = await AppIdentity.getOrCreateUserId();

      final payload = <String, dynamic>{
        'user_id': userId,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
        'e_mail': email,
        'app_version': AppIdentity.appVersion,
      };

      // Prefer Uri.https to avoid any subtle parsing issues.
      final uri = Uri.https('medisom.com.br', '/iot/app/request-verification-code');

       debugPrint('request-verification-code: POST $uri');
       debugPrint('request-verification-code: payload=${jsonEncode(payload)}');
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
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Após 200 OK: abrir a tela de digitação do código (6 dígitos).
        final loc = Uri(
          path: AppRoutes.verifyCode,
          queryParameters: {
            'e_mail': email,
            'user_id': userId,
            if (deviceId.isNotEmpty) 'device_id': deviceId,
          },
        ).toString();

        // We still pass `extra` for normal in-session navigation, but the query params
        // make the flow resilient if iOS restores the route without `extra`.
        context.push(loc, extra: VerifyCodeExtra(email: email, userId: userId, deviceId: deviceId));
      } else if (resp.statusCode == 409) {
        final bodyText = _decodeResponseBody(resp);
        debugPrint('request-verification-code conflict: ${resp.statusCode} $bodyText');
        await _showExistingAccountDialog(email: email);
      } else {
        final bodyText = _decodeResponseBody(resp);
        debugPrint('request-verification-code failed: ${resp.statusCode} $bodyText');

        final apiMsg = _tryParseApiMessage(bodyText);
        debugPrint('request-verification-code parsed message: ${apiMsg ?? '(null)'}');
        final message = apiMsg ?? 'Não foi possível enviar o código. (${resp.statusCode})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('request-verification-code timeout: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tempo esgotado (5s) ao conectar. Verifique sua internet e tente novamente.')),
      );
    } on http.ClientException catch (e) {
      // Em geral, o http encapsula SocketException aqui. No Web pode ser CORS/bloqueio do navegador.
      debugPrint('request-verification-code client exception: $e');
      if (!mounted) return;

      final msg = e.toString();
      final isDns = msg.contains('Failed host lookup') || msg.contains('No address associated with hostname');
      final isCorsOrWebBlocked = kIsWeb && (msg.contains('XMLHttpRequest') || msg.contains('CORS') || msg.contains('Origin'));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDns
                ? 'Sem acesso ao servidor (falha de DNS). Verifique internet/DNS do device/emulador.'
                : isCorsOrWebBlocked
                    ? 'No navegador, a chamada pode estar bloqueada (CORS). Teste em Android/iOS ou libere CORS no servidor.'
                    : 'Falha de conexão com o servidor. Verifique sua internet e tente novamente.',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('request-verification-code unexpected error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;

      final msg = e.toString();
      final isCorsOrWebBlocked = kIsWeb && (msg.contains('XMLHttpRequest') || msg.contains('CORS') || msg.contains('Origin') || msg.contains('Failed to fetch'));
      if (isCorsOrWebBlocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No navegador, a chamada pode estar bloqueada (CORS/rede).')),
        );
        return;
      }

      if (kDebugMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar código: $msg')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao solicitar código. Tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ResponsiveAuthScaffold(
      title: 'Criar sua conta',
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  // Quando o usuário chega aqui via `context.go('/register')`,
                  // não existe stack para `pop()`. Então fazemos fallback.
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/splash');
                  }
                },
                icon: Icon(Icons.arrow_back, color: cs.onSurface),
                tooltip: 'Voltar',
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Registrar', style: context.textStyles.titleLarge)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email)),
          ),
          const SizedBox(height: AppSpacing.lg),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _email,
            builder: (context, value, child) {
              final raw = value.text;
              final shouldShow = raw.contains('@');
              if (!shouldShow) return const SizedBox.shrink();
              return PrimaryButton(
                onPressed: _loading ? null : _requestVerificationCode,
                label: 'Obter código de verificação',
                icon: Icons.mark_email_read_outlined,
                isLoading: _loading,
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Ao registrar, você poderá validar o e-mail e selecionar o sensor quando tiver acesso a múltiplas sensores.',
            style: context.textStyles.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class AppRadii {
}
