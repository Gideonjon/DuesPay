// POST /api/paga-webhook
// Paga calls this when a payment request changes state. It is the only place
// a payment becomes "paid", and only after the callback hash checks out.
const { markPaid, markExpired } = require('../lib/firebase');
const { isCallbackAuthentic } = require('../lib/paga');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Use POST.' });

  let payload;
  try {
    payload = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  } catch (_) {
    return res.status(400).json({ error: 'Invalid JSON.' });
  }

  if (!isCallbackAuthentic(payload, process.env.PAGA_HASH_KEY || '')) {
    console.warn('Rejected callback with a bad hash. Fields received:', Object.keys(payload));
    return res.status(401).json({ error: 'Bad hash.' });
  }

  const reference = String(payload.externalReferenceNumber || '');
  const event = String(payload.event || '').toUpperCase();
  const state = String(payload.state || '').toUpperCase();

  try {
    if (event === 'PAYMENT_COMPLETE' && String(payload.statusCode) === '0') {
      const funding = payload.fundingDetails || {};
      const result = await markPaid(reference, {
        pagaNotificationId: payload.notificationId || null,
        paidAmount: Number(payload.paymentAmount ?? 0),
        payerBankName: funding.payerBankName || null,
        senderName: funding.payerName || null,
      });
      console.log(`Callback ${reference}: ${result}`);
    } else if (event.includes('EXPIRE') || state.includes('EXPIRE')) {
      const result = await markExpired(reference);
      console.log(`Callback ${reference}: ${result}`);
    } else {
      console.log(`Callback ${reference}: ignored event=${event} state=${state}`);
    }
  } catch (err) {
    // A non-200 makes Paga retry, which is what we want if Firestore hiccups.
    console.error('paga-webhook failed:', err);
    return res.status(500).json({ error: 'Temporary failure.' });
  }

  return res.status(200).json({ status: 'SUCCESS' });
};
