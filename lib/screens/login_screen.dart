import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/session.dart';
import '../theme.dart';
import '../ui.dart';

enum _Mode { owner, staff, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _Mode _mode = _Mode.owner;
  bool _busy = false;
  String? _error;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _shopName = TextEditingController();
  final _ownerName = TextEditingController();
  final _shopCode = TextEditingController();
  final _username = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _shopName.dispose();
    _ownerName.dispose();
    _shopCode.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<SessionState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.owner:
          await session.signInOwner(_email.text.trim(), _password.text);
          break;
        case _Mode.staff:
          await session.signInStaff(
              _shopCode.text.trim(), _username.text.trim(), _password.text);
          break;
        case _Mode.register:
          if (_shopName.text.trim().isEmpty || _ownerName.text.trim().isEmpty) {
            throw 'Enter your shop name and your name.';
          }
          if (_password.text.length < 6) {
            throw 'Password must be at least 6 characters.';
          }
          await session.registerOwner(
            email: _email.text.trim(),
            password: _password.text,
            shopName: _shopName.text.trim(),
            ownerName: _ownerName.text.trim(),
          );
          break;
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.purpleLight, AppColors.purpleDark],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purple.withValues(alpha: 0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.storefront,
                        size: 44, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                const SizedBox(height: 8),
                Text(AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Inventory, sales and credit for your shop',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.owner, label: Text('Owner')),
                    ButtonSegment(value: _Mode.staff, label: Text('Staff')),
                    ButtonSegment(value: _Mode.register, label: Text('New shop')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 20),
                if (_mode == _Mode.register) ...[
                  TextField(
                    controller: _shopName,
                    decoration: const InputDecoration(labelText: 'Shop name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ownerName,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_mode == _Mode.staff) ...[
                  TextField(
                    controller: _shopCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Shop code',
                        helperText: 'Ask the owner for the 6-letter shop code'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                ] else
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_mode == _Mode.register ? 'Create my shop' : 'Sign in'),
                ),
                if (_mode == _Mode.staff)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Staff accounts are created by the shop owner. '
                      'You cannot sign up yourself.',
                      textAlign: TextAlign.center,
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
