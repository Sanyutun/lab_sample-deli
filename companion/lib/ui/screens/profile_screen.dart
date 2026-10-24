import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/strings.dart';
import 'settings_screen.dart';

/// The signed-in delivery man's identity and a way into settings. Personal
/// details come from the office account; they are read-only here.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final profile = services.auth.profile;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.teal.shade100,
                child: const Icon(Icons.person, size: 40, color: Colors.teal),
              ),
              const SizedBox(height: 12),
              Text(
                profile?.name ?? S.dash,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text('${S.deliveryIdLabel}: ${profile?.id ?? S.dash}'),
              const SizedBox(height: 20),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text(S.deliveryIdLabel),
                subtitle: Text(profile?.id ?? S.dash),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text(S.phone),
                subtitle: Text(
                  (profile?.phone.isNotEmpty ?? false) ? profile!.phone : S.dash,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.wifi_tethering),
                title: const Text(S.officeServer),
                subtitle: Text(
                  services.config.isConfigured
                      ? services.config.serverUrl
                      : S.notSet,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings),
            title: const Text(S.settingsAndLogout),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          S.profileNote,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
