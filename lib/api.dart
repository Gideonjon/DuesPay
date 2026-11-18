import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class PaymentInstructions {
  PaymentInstructions({
    required this.referenceNumber,
    required this.accountNumber,
    required this.bankName,
    required this.amountToPay,
  });

  final String referenceNumber;
  final String accountNumber;
  final String bankName;
  final num amountToPay;
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Asks the backend to create a Paga payment request for one student.
Future<PaymentInstructions> createPayment({
  required String dueCode,
  required String payerName,
  required String matricNo,
  required String phone,
}) async {
  final http.Response response;
  try {
    response = await http
        .post(
          Uri.parse('$backendUrl/api/create-payment'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'dueCode': dueCode,
            'payerName': payerName,
            'matricNo': matricNo,
            'phone': phone,
          }),
        )
        .timeout(const Duration(seconds: 30));
  } catch (_) {
    throw ApiException('Could not reach the server. Check your connection.');
  }

  Map<String, dynamic> data = {};
  try {
    data = jsonDecode(response.body) as Map<String, dynamic>;
  } catch (_) {
    // Fall through with an empty map; handled below.
  }

  if (response.statusCode != 200) {
    throw ApiException(
      (data['error'] as String?) ?? 'Something went wrong. Please try again.',
    );
  }

  return PaymentInstructions(
    referenceNumber: data['referenceNumber'] as String,
    accountNumber: data['accountNumber'] as String,
    bankName: (data['bankName'] as String?) ?? 'Paga',
    amountToPay: (data['amountToPay'] as num?) ?? 0,
  );
}
