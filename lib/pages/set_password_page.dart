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

class SetPasswordExtra {
  final String userId;
  final String deviceId;
  final String email;

  const SetPasswordExtra({required this.userId, required this.deviceId, required this.email});
}

class SetPasswordPage extends StatefulWidget {
  final Object? extra;

  const SetPasswordPage({super.key, required this.extra});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _serverMessage;

  SetPasswordExtra? get _extra {
    final e = widget.extra;
    if (e is SetPasswordExtra) return e;
    if (e is Map) {
      try {
        final userId = (e['user_id'] ?? '').toString();
        final deviceId = (e['device_id'] ?? '').toString();
        final email = (e['email'] ?? e['e_mail'] ?? '').toString();
        if (userId.isNotEmpty && email.isNotEmpty) return SetPasswordExtra(userId: userId, deviceId: deviceId, email: email);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _meetsRequirements {
    final p = _password.text;
    if (p.length < 6 || p.length > 20) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(p);
    final hasNumber = RegExp(r'\d').hasMatch(p);
    return hasLetter && hasNumber;
  }

  String _decodeResponseBody(http.Response resp) {
    try {
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('set-password decode failed: $e');
      return resp.body;
    }
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

  Future<void> _submit() async {
    final extra = _extra;
    if (extra == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados inválidos. Volte e tente novamente.')));
      return;
    }

    if (!_meetsRequirements) {
      setState(() => _serverMessage = 'Use de 6 a 20 caracteres, misturando letras e números');
      return;
    }

    setState(() {
      _loading = true;
      _serverMessage = null;
    });

    try {
      final deviceId = extra.deviceId.isNotEmpty ? extra.deviceId : await AppIdentity.getOrCreateDeviceId();
      final payload = <String, dynamic>{
        'user_id': extra.userId,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
        'e_mail': extra.email.trim(),
        'password': _password.text,
        'app_version': AppIdentity.appVersion,
      };

      final uri = Uri.https('medisom.com.br', '/iot/app/set-password');
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
        final apiMsg = decoded != null ? (decoded['message'] ?? decoded['mensagem'])?.toString() : null;
        final msg = (apiMsg != null && apiMsg.trim().isNotEmpty) ? apiMsg.trim() : 'Senha cadastrada com sucesso.';
        setState(() => _serverMessage = msg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final encodedEmail = Uri.encodeQueryComponent(extra.email.trim());
        final encodedPassword = Uri.encodeQueryComponent(_password.text);
        context.go('${AppRoutes.login}?email=$encodedEmail&password=$encodedPassword');
      } else {
        debugPrint('set-password failed: ${resp.statusCode} $bodyText');
        final decoded = _tryParseApiMap(bodyText);
        final apiMsg = decoded != null ? (decoded['message'] ?? decoded['mensagem'])?.toString() : null;
        final msg = (apiMsg != null && apiMsg.trim().isNotEmpty) ? apiMsg.trim() : 'Não foi possível cadastrar a senha. (${resp.statusCode})';
        setState(() => _serverMessage = msg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on TimeoutException catch (e) {
      debugPrint('set-password timeout: $e');
      if (!mounted) return;
      setState(() => _serverMessage = 'Tempo esgotado ao cadastrar a senha. Tente novamente.');
    } on http.ClientException catch (e) {
      debugPrint('set-password client exception: $e');
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
      });
    } catch (e) {
      debugPrint('set-password unexpected error: $e');
      if (!mounted) return;
      setState(() => _serverMessage = 'Erro ao cadastrar a senha. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final extra = _extra;

    return ResponsiveAuthScaffold(
      title: 'Configurar senha',
      subtitle: extra?.email ?? '',
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
              Expanded(child: Text('Configurar senha', style: context.textStyles.titleLarge)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_serverMessage != null) setState(() => _serverMessage = null);
              setState(() {});
            },
            onSubmitted: (_) => _loading ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: cs.onSurfaceVariant),
                tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Use de 6 a 20 caracteres, misturando letras e números',
            style: context.textStyles.bodyMedium?.copyWith(
              height: 1.2,
              color: _password.text.isEmpty
                  ? cs.onSurfaceVariant
                  : (_meetsRequirements ? Colors.green : Colors.red),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            onPressed: (_loading || !_meetsRequirements) ? null : _submit,
            label: 'Concluído',
            icon: Icons.check_circle_outline,
            isLoading: _loading,
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
        ],
      ),
    );
  }
}
