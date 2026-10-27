import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session.dart';

/// Shown when the shop's subscription has ended or the owner has switched
/// a staff member off. Nothing is deleted; access returns when renewed.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text(session.blockedReason,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Your data is safe and will be here when access returns.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => session.refreshMembership(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => session.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
