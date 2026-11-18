
'use strict';

// Paga Collect API helpers.
// Docs: https://developer-docs.paga.com/docs/operations-1

const crypto = require('crypto');

// --------------------------------------------------
// Fee share configuration and validation
// --------------------------------------------------

const payerFeeShare = Number(process.env.PAYER_FEE_SHARE ?? 0.99);
const payeeFeeShare = Number(process.env.PAYEE_FEE_SHARE ?? 0);

if (
  !Number.isFinite(payerFeeShare) ||
  !Number.isFinite(payeeFeeShare) ||
  payerFeeShare < 0 ||
  payeeFeeShare < 0 ||
  payerFeeShare + payeeFeeShare >= 1
) {
  throw new Error(
    'Paga fee shares must be non-negative and total less than 1.0.'
  );
}

// --------------------------------------------------
// SHA512 hashing
// --------------------------------------------------

function sha512(text) {
  return crypto
    .createHash('sha512')
    .update(text, 'utf8')
    .digest('hex');
}

// Hash for POST /paymentRequest.
// Field order is fixed by Paga; missing fields are skipped.

function paymentRequestHash(body, hashKey) {
  const payer = body.payer || {};
  const payee = body.payee || {};

  const parts = [
    body.referenceNumber,
    body.amount,
    body.currency,
    payer.phoneNumber,
    payer.email,
    payee.accountNumber,
    payee.phoneNumber,
    payee.bankId,
    payee.bankAccountNumber,
  ];

  const joined = parts
    .filter((p) => p !== undefined && p !== null && p !== '')
    .join('');

  return sha512(joined + hashKey);
}

// --------------------------------------------------
// Callback balance formatting
// --------------------------------------------------

function formatBalance(value) {
  if (value === undefined || value === null || value === '') {
    return '';
  }

  const n = Number(value);

  return Number.isFinite(n) ? n.toFixed(2) : String(value);
}

// --------------------------------------------------
// Paga callback hash verification
// --------------------------------------------------

function callbackHash(payload, hashKey) {
  const joined =
    String(payload.notificationId ?? '') +
    String(payload.statusCode ?? '') +
    String(payload.externalReferenceNumber ?? '') +
    String(payload.state ?? '') +
    formatBalance(payload.outstandingBalance);

  return sha512(joined + hashKey);
}

function safeEqualHex(a, b) {
  const x = Buffer.from(String(a || '').toLowerCase());
  const y = Buffer.from(String(b || '').toLowerCase());

  return (
    x.length === y.length &&
    crypto.timingSafeEqual(x, y)
  );
}

function isCallbackAuthentic(payload, hashKey) {
  return safeEqualHex(
    payload && payload.hash,
    callbackHash(payload || {}, hashKey)
  );
}

// --------------------------------------------------
// Paga environment configuration
// --------------------------------------------------

function config() {
  const {
    PAGA_PUBLIC_KEY,
    PAGA_SECRET_KEY,
    PAGA_HASH_KEY,
  } = process.env;

  if (!PAGA_PUBLIC_KEY || !PAGA_SECRET_KEY || !PAGA_HASH_KEY) {
    throw new Error(
      'Paga keys are not set (PAGA_PUBLIC_KEY, PAGA_SECRET_KEY, PAGA_HASH_KEY).'
    );
  }

  return {
    publicKey: PAGA_PUBLIC_KEY,
    secretKey: PAGA_SECRET_KEY,
    hashKey: PAGA_HASH_KEY,

    baseUrl: (
      process.env.PAGA_BASE_URL ||
      'https://beta-collect.paga.com'
    ).replace(/\/+$/, ''),
  };
}

// --------------------------------------------------
// Extract bank transfer account details
// --------------------------------------------------

function extractBankTransfer(data) {
  const methods = Array.isArray(data.paymentMethods)
    ? data.paymentMethods
    : [];

  const method =
    methods.find((m) => m && m.name === 'BANK_TRANSFER') ||
    methods[0] ||
    {};

  const props = method.properties || {};

  return {
    accountNumber:
      props.AccountNumber ||
      props.accountNumber ||
      null,

    bankName:
      props.BankName ||
      props.bankName ||
      null,
  };
}

// --------------------------------------------------
// Create Paga payment request
// --------------------------------------------------

async function createPaymentRequest({
  referenceNumber,
  amount,
  payerName,
  payerPhone,
  payeeName,
  callBackUrl,
}) {
  const cfg = config();

  if (!referenceNumber || !amount || !payerPhone || !callBackUrl) {
    throw new Error(
      'Missing required Paga payment request parameters.'
    );
  }

  const numericAmount = Number(amount);

  if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
    throw new Error('Payment amount must be greater than zero.');
  }

  const expiryMinutes = Number(
    process.env.PAYMENT_EXPIRY_MINUTES || 30
  );

  if (!Number.isFinite(expiryMinutes) || expiryMinutes <= 0) {
    throw new Error('PAYMENT_EXPIRY_MINUTES must be greater than zero.');
  }

  const expiry = new Date(
    Date.now() + expiryMinutes * 60 * 1000
  );

  const body = {
    referenceNumber,
    amount: numericAmount,
    currency: 'NGN',

    payer: {
      name: payerName,
      phoneNumber: payerPhone,
    },

    payee: {
      name: payeeName,
    },

    expiryDateTimeUTC: expiry.toISOString().slice(0, 19),

    isSuppressMessages: true,

    payerCollectionFeeShare: payerFeeShare,
    payeeCollectionFeeShare: payeeFeeShare,

    isAllowPartialPayments: false,
    isAllowOverPayments: false,

    callBackUrl,

    paymentMethods: ['BANK_TRANSFER'],
  };

  const res = await fetch(
    `${cfg.baseUrl}/paymentRequest`,
    {
      method: 'POST',

      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',

        Authorization:
          'Basic ' +
          Buffer.from(
            `${cfg.publicKey}:${cfg.secretKey}`
          ).toString('base64'),

        hash: paymentRequestHash(body, cfg.hashKey),
      },

      body: JSON.stringify(body),
    }
  );

  const responseText = await res.text();

  let data;

  try {
    data = JSON.parse(responseText);
  } catch (_) {
    throw new Error(
      `Paga returned a non-JSON response (HTTP ${res.status}): ${responseText.slice(0, 200)}`
    );
  }

  if (!res.ok || String(data.statusCode) !== '0') {
    throw new Error(
      `Paga rejected the request (HTTP ${res.status}): ${
        data.statusMessage || responseText.slice(0, 200)
      }`
    );
  }

  const transfer = extractBankTransfer(data);

  if (!transfer.accountNumber) {
    throw new Error(
      'Paga response had no bank transfer account number: ' +
      responseText.slice(0, 300)
    );
  }

  return {
    accountNumber: transfer.accountNumber,

    bankName:
      transfer.bankName ||
      data.bankName ||
      'Paga',

    amountToPay: Number(
      data.totalPaymentAmount ??
      data.requestAmount ??
      numericAmount
    ),

    expiresAt: expiry,
  };
}

// --------------------------------------------------
// Module exports
// --------------------------------------------------

module.exports = {
  sha512,
  paymentRequestHash,
  callbackHash,
  formatBalance,
  isCallbackAuthentic,
  createPaymentRequest,
  extractBankTransfer,
};
