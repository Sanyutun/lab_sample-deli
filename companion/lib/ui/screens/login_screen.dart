// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/failure.dart';
import '../../core/strings.dart';
import '../widgets/server_url_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _pinController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _loginController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final services = AppScope.of(context);
    if (!services.config.isConfigured) {
      await showServerUrlDialog(context, services);
      if (!services.config.isConfigured) return;
    }
    setState(() => _busy = true);
    try {
      await services.auth.login(
        loginId: _loginController.text.trim(),
        pin: _pinController.text,
      );
      // The root listens to the auth controller and swaps to the dashboard.
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icon/app_icon.png', width: 64, height: 64),
                const SizedBox(height: 12),
                Text(
                  S.appName,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  S.loginSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _loginController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: S.deliveryId,
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: S.pin,
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _login(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(S.signIn),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => showServerUrlDialog(context, services),
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(
                    services.config.isConfigured
                        ? S.serverLabel(services.config.serverUrl)
                        : S.setServerAddress,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
