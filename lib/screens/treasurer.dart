import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';

/// Shows sign-in until a treasurer is logged in, then their dues.
class TreasurerGate extends StatelessWidget {
  const TreasurerGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        return user == null ? const SignInScreen() : DuesListScreen(user: user);
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      final email = _email.text.trim();
      final password = _password.text;
      if (_creating) {
        await auth.createUserWithEmailAndPassword(email: email, password: password);
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_creating ? 'Create account' : 'Treasurer sign in')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Password', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_loading
                  ? 'Please wait...'
                  : (_creating ? 'Create account' : 'Sign in')),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _creating = !_creating),
            child: Text(_creating
                ? 'I already have an account'
                : 'New treasurer? Create an account'),
          ),
        ],
      ),
    );
  }
}

class DuesListScreen extends StatelessWidget {
  const DuesListScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final dues = FirebaseFirestore.instance
        .collection('dues')
        .where('ownerUid', isEqualTo: user.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your dues'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New due'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CreateDueScreen(user: user)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: dues,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your dues.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No dues yet. Tap "New due" to create one.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final due = doc.data();
              final collected = (due['collectedTotal'] as num?) ?? 0;
              final paidCount = (due['paidCount'] as num?) ?? 0;
              return ListTile(
                title: Text((due['title'] as String?) ?? 'Due'),
                subtitle: Text('${naira(collected)} from $paidCount paid'),
                trailing: Text(doc.id,
                    style: Theme.of(context).textTheme.labelLarge),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DueDashboardScreen(code: doc.id, user: user),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CreateDueScreen extends StatefulWidget {
  const CreateDueScreen({super.key, required this.user});

  final User user;

  @override
  State<CreateDueScreen> createState() => _CreateDueScreenState();
}

class _CreateDueScreenState extends State<CreateDueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Six characters, skipping look-alikes such as 0/O and 1/I.
  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final code = _newCode();
    try {
      await FirebaseFirestore.instance.collection('dues').doc(code).set({
        'title': _title.text.trim(),
        'amount': int.parse(_amount.text.trim()),
        'ownerUid': widget.user.uid,
        'collectedTotal': 0,
        'paidCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DueDashboardScreen(code: code, user: widget.user),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the due. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New due')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'NACOS dues 2026/27',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Amount per student',
                prefixText: '₦ ',
              ),
              validator: (value) {
                final amount = int.tryParse((value ?? '').trim());
                if (amount == null) return 'Enter an amount';
                return amount < 100 ? 'Minimum is ₦100' : null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_saving ? 'Creating...' : 'Create due'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live view of one due: totals at the top, payments below.
class DueDashboardScreen extends StatelessWidget {
  const DueDashboardScreen({super.key, required this.code, required this.user});

  final String code;
  final User user;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final dueStream = firestore.collection('dues').doc(code).snapshots();
    final paymentsStream = firestore
        .collection('payments')
        .where('ownerUid', isEqualTo: user.uid)
        .where('dueId', isEqualTo: code)
        .snapshots();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: dueStream,
            builder: (context, snapshot) {
              final due = snapshot.data?.data() ?? const <String, dynamic>{};
              final collected = (due['collectedTotal'] as num?) ?? 0;
              final paidCount = (due['paidCount'] as num?) ?? 0;
              final amount = (due['amount'] as num?) ?? 0;
              return Container(
                width: double.infinity,
                color: theme.colorScheme.primaryContainer,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((due['title'] as String?) ?? '',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(naira(collected),
                        style: theme.textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('$paidCount paid  ·  ${naira(amount)} each'),
                    const SizedBox(height: 16),
                    Text('Due code: $code',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final link = payLink(code);
                      final title = (due['title'] as String?) ?? 'dues';
                      final message = link == null
                          ? 'Pay $title on DuesPay with code $code'
                          : 'Pay $title on DuesPay: $link';
                      return OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: Text(link == null ? 'Copy code' : 'Copy pay link'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: message));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(link == null
                                  ? 'Copied. Paste it in your class group chat.'
                                  : 'Pay link copied. Paste it in your class group chat.'),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: paymentsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Could not load payments.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final payments =
                    snapshot.data!.docs.map((doc) => doc.data()).toList();
                // Paid first, then newest first. Sorted here to avoid a Firestore index.
                payments.sort((a, b) {
                  final aPaid = a['status'] == 'paid' ? 0 : 1;
                  final bPaid = b['status'] == 'paid' ? 0 : 1;
                  if (aPaid != bPaid) return aPaid - bPaid;
                  final aTime = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  final bTime = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  return bTime.compareTo(aTime);
                });
                if (payments.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No payments yet. Share the code with your coursemates.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    final status = (payment['status'] as String?) ?? 'pending';
                    final paid = status == 'paid';
                    return ListTile(
                      leading: Icon(
                        paid ? Icons.check_circle : Icons.schedule,
                        color: paid
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text((payment['payerName'] as String?) ?? ''),
                      subtitle: Text((payment['matricNo'] as String?) ?? ''),
                      trailing: Text(paid ? 'Paid' : status),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
