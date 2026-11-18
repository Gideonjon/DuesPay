// POST /api/create-payment
// Body: { dueCode, payerName, matricNo, phone }
// Returns the bank account number the student should transfer to.
const crypto = require('crypto');
const { db, FieldValue } = require('../lib/firebase');
const { createPaymentRequest } = require('../lib/paga');

function clean(value, max) {
  return String(value ?? '').trim().slice(0, max);
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Use POST.' });

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
    const dueCode = clean(body.dueCode, 12).toUpperCase();
    const payerName = clean(body.payerName, 80);
    const matricNo = clean(body.matricNo, 30);
    const phone = clean(body.phone, 15).replace(/[^\d+]/g, '');

    if (!dueCode || !payerName || !matricNo) {
      return res.status(400).json({ error: 'dueCode, payerName and matricNo are required.' });
    }
    if (!/^(\+?234|0)\d{10}$/.test(phone)) {
      return res.status(400).json({ error: 'Enter a valid Nigerian phone number.' });
    }

    const store = db();
    const dueSnap = await store.collection('dues').doc(dueCode).get();
    if (!dueSnap.exists) return res.status(404).json({ error: 'No due found with that code.' });
    const due = dueSnap.data();

    const base = (process.env.PUBLIC_BASE_URL || `https://${req.headers.host}`).replace(/\/+$/, '');
    const referenceNumber = `DP${Date.now()}${crypto.randomBytes(4).toString('hex')}`;

    const paga = await createPaymentRequest({
      referenceNumber,
      amount: due.amount,
      payerName,
      payerPhone: phone,
      payeeName: clean(due.title, 40) || 'DuesPay',
      callBackUrl: `${base}/api/paga-webhook`,
    });

    await store.collection('payments').doc(referenceNumber).set({
      dueId: dueCode,
      ownerUid: due.ownerUid,
      payerName,
      matricNo,
      phone,
      amount: due.amount,
      amountToPay: paga.amountToPay,
      accountNumber: paga.accountNumber,
      bankName: paga.bankName,
      status: 'pending',
      expiresAt: paga.expiresAt,
      createdAt: FieldValue.serverTimestamp(),
    });

    return res.status(200).json({
      referenceNumber,
      accountNumber: paga.accountNumber,
      bankName: paga.bankName,
      amountToPay: paga.amountToPay,
      expiresAt: paga.expiresAt.toISOString(),
    });
  } catch (err) {
    console.error('create-payment failed:', err);
    return res.status(502).json({ error: 'Could not start the payment. Please try again.' });
  }
};
