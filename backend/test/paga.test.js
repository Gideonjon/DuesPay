const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const paga = require('../lib/paga');

const sha = (s) => crypto.createHash('sha512').update(s).digest('hex');

test('payment request hash uses the documented field order and skips blanks', () => {
  const body = {
    referenceNumber: 'DP1',
    amount: 2000,
    currency: 'NGN',
    payer: { name: 'Ada', phoneNumber: '08012345678' },
    payee: { name: 'CSC Dues' },
  };
  assert.strictEqual(paga.paymentRequestHash(body, 'KEY'), sha('DP12000NGN08012345678KEY'));
});

test('callback hash formats the balance to two decimals', () => {
  const payload = {
    notificationId: 'n1',
    statusCode: '0',
    externalReferenceNumber: 'DP1',
    state: 'CONSUMED',
    outstandingBalance: 0,
  };
  assert.strictEqual(paga.callbackHash(payload, 'KEY'), sha('n10DP1CONSUMED0.00KEY'));
});

test('callback hash leaves out a null balance', () => {
  const payload = { notificationId: 'n1', statusCode: '0', externalReferenceNumber: 'DP1', state: 'CONSUMED', outstandingBalance: null };
  assert.strictEqual(paga.callbackHash(payload, 'KEY'), sha('n10DP1CONSUMEDKEY'));
});

test('authentic callbacks pass and tampered ones fail', () => {
  const payload = { notificationId: 'n1', statusCode: '0', externalReferenceNumber: 'DP1', state: 'CONSUMED', outstandingBalance: 0 };
  payload.hash = paga.callbackHash(payload, 'KEY').toUpperCase();
  assert.ok(paga.isCallbackAuthentic(payload, 'KEY'));
  assert.ok(!paga.isCallbackAuthentic({ ...payload, externalReferenceNumber: 'DP2' }, 'KEY'));
  assert.ok(!paga.isCallbackAuthentic({ ...payload, hash: undefined }, 'KEY'));
});

test('account number is read from the bank transfer method', () => {
  const data = { paymentMethods: [{ name: 'BANK_TRANSFER', properties: { AccountNumber: '0856712865' } }] };
  assert.strictEqual(paga.extractBankTransfer(data).accountNumber, '0856712865');
  assert.strictEqual(paga.extractBankTransfer({}).accountNumber, null);
});
