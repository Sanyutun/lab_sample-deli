import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/formatters.dart';
import '../../core/strings.dart';
import '../widgets/server_url_dialog.dart';

/// Settings and sign-out. Nothing secret is shown; the session token stays in
/// secure storage and is discarded on logout.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final services = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.logoutQuestion),
        content: const Text(S.logoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.logout),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await services.auth.logout();
    // The root listens to the auth controller and returns to the login screen.
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text(S.officeServerAddress),
            subtitle: Text(
              services.config.isConfigured
                  ? services.config.serverUrl
                  : S.notSetTapToEnter,
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => showServerUrlDialog(context, services),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text(S.locationCaptured),
            subtitle: Text(
              S.aboutEvery(fmtMinutes(services.tracking.interval)),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text(S.sentLocationsKept),
            subtitle: Text(
              S.setByOffice(fmtMinutes(services.tracking.retention)),
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(S.readOnlyNote, style: TextStyle(fontSize: 12)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              S.logout,
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}
