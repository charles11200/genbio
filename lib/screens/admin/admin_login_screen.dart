import 'package:flutter/material.dart';
import '../../data/database_helper.dart';
import '../../services/password_utils.dart';

/// Handles both first-run setup (no admin exists yet -> create one) and
/// normal login. Never ships a hardcoded default password in the APK -
/// the very first admin account is created by whoever installs the app.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _checkingFirstRun = true;
  bool _isFirstRun = false;

  @override
  void initState() {
    super.initState();
    _checkFirstRun();
  }

  Future<void> _checkFirstRun() async {
    final admin = await DatabaseHelper.instance.getAdmin();
    setState(() {
      _isFirstRun = admin == null;
      _checkingFirstRun = false;
    });
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.length < 6) {
      setState(() => _error = 'Username required, password must be 6+ characters.');
      return;
    }

    if (_isFirstRun) {
      final hash = PasswordUtils.hash(password);
      await DatabaseHelper.instance.upsertAdmin(username, hash);
      if (mounted) _goToDashboard();
      return;
    }

    final admin = await DatabaseHelper.instance.getAdmin();
    if (admin != null &&
        admin['username'] == username &&
        PasswordUtils.verify(password, admin['passwordHash'] as String)) {
      if (mounted) _goToDashboard();
    } else {
      setState(() => _error = 'Incorrect username or password.');
    }
  }

  void _goToDashboard() {
    // TODO: Navigator.pushReplacement to AdminDashboardScreen once built
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged in - dashboard screen not built yet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingFirstRun) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isFirstRun ? 'Create Admin Account' : 'Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isFirstRun)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'No admin account exists yet. Create one now - '
                      'this will be required to edit questions later.',
                ),
              ),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: Text(_isFirstRun ? 'Create Account' : 'Log In'),
            ),
          ],
        ),
      ),
    );
  }
}