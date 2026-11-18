import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../config.dart';

/// Step 1: the student types the code the treasurer shared.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key, this.initialCode});

  /// Pre-filled from a pay link; looked up straight away.
  final String? initialCode;

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode ?? '';
    if (initial.isNotEmpty) {
      _code.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookUp();
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap =
          await FirebaseFirestore.instance.collection('dues').doc(code).get();
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _error = 'No due found with that code.');
        return;
      }
      final due = snap.data()!;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PayerDetailsScreen(
            dueCode: code,
            title: (due['title'] as String?) ?? 'Due',
            amount: (due['amount'] as num?) ?? 0,
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load that due. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pay a due')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter the code from your treasurer.'),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Due code', errorText: _error),
              onSubmitted: (_) => _lookUp(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _lookUp,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_loading ? 'Checking...' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 2: who is paying.
class PayerDetailsScreen extends StatefulWidget {
  const PayerDetailsScreen({
    super.key,
    required this.dueCode,
    required this.title,
    required this.amount,
  });

  final String dueCode;
  final String title;
  final num amount;

  @override
  State<PayerDetailsScreen> createState() => _PayerDetailsScreenState();
}

class _PayerDetailsScreenState extends State<PayerDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _matric = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _matric.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final instructions = await createPayment(
        dueCode: widget.dueCode,
        payerName: _name.text.trim(),
        matricNo: _matric.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TransferScreen(
            title: widget.title,
            instructions: instructions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(naira(widget.amount),
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: _required,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _matric,
              decoration: const InputDecoration(labelText: 'Matric number'),
              validator: _required,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '08012345678',
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 11 ? 'Enter a valid phone number' : null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_loading ? 'Getting account...' : 'Get account number'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 3: show the account number and wait for Paga to confirm the transfer.
class TransferScreen extends StatelessWidget {
  const TransferScreen({
    super.key,
    required this.title,
    required this.instructions,
  });

  final String title;
  final PaymentInstructions instructions;

  @override
  Widget build(BuildContext context) {
    final payment = FirebaseFirestore.instance
        .collection('payments')
        .doc(instructions.referenceNumber)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: payment,
        builder: (context, snapshot) {
          final status = snapshot.data?.data()?['status'] as String? ?? 'pending';
          if (status == 'paid') return _Paid(amount: instructions.amountToPay);
          if (status == 'expired') return const _Expired();
          return _Waiting(instructions: instructions);
        },
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.instructions});

  final PaymentInstructions instructions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Transfer exactly this amount from any bank app:'),
        const SizedBox(height: 8),
        Text(naira(instructions.amountToPay),
            style: theme.textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bank', style: theme.textTheme.labelMedium),
                Text(instructions.bankName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('Account number', style: theme.textTheme.labelMedium),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        instructions.accountNumber,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(letterSpacing: 2),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: instructions.accountNumber));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account number copied')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text('Waiting for your transfer. Keep this screen open.'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Paid extends StatelessWidget {
  const _Paid({required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 96, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Payment received', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${naira(amount)} confirmed. Your treasurer can see it now.',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Expired extends StatelessWidget {
  const _Expired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_off_outlined, size: 72),
            const SizedBox(height: 16),
            const Text('This account number has expired.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Start again'),
            ),
          ],
        ),
      ),
    );
  }
}
