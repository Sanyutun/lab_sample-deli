import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/office_link.dart';
import '../domain/exceptions.dart';
import 'dashboard_screen.dart';
import 'office_link_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.link = OfficeLink.local,
    this.onReconnect,
  });

  /// Where this terminal's data comes from (its own database or a server).
  final OfficeLink link;

  /// Called after the user changes the server settings.
  final Future<void> Function(OfficeLink)? onReconnect;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _editServer() async {
    final chosen = await showOfficeLinkDialog(context, widget.link);
    if (chosen == null) return;
    await widget.onReconnect?.call(chosen);
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final services = AppScope.of(context);
      final user = await services.auth.login(_pinController.text);
      // Opens the day's PINs if the app stayed open past midnight.
      await services.dailyPins.ensureToday();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              DashboardScreen(userName: user.name, isAdmin: user.isAdmin),
        ),
      );
    } on AppException catch (e) {
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/app_icon.png', width: 72, height: 72),
              const SizedBox(height: 12),
              Text(
                'TWOK Sample Deli - Office',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Delivery-man commissions',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinController,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 16),
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
                      : const Text('LOGIN'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Admin PIN 1234 · Staff PIN 1111',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _editServer,
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: Text(
                  widget.link.isConfigured
                      ? 'Server: ${widget.link.url}'
                      : 'Server: this device (local)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
