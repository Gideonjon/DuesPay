// Firestore access with admin rights. Only the backend can mark a payment as paid.
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

function db() {
  if (!getApps().length) {
    const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
    if (!b64) throw new Error('FIREBASE_SERVICE_ACCOUNT_B64 is not set.');
    const serviceAccount = JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
    initializeApp({ credential: cert(serviceAccount) });
  }
  return getFirestore();
}

// Marks a payment paid exactly once and adds it to the due's running totals.
async function markPaid(referenceNumber, details) {
  const store = db();
  const payRef = store.collection('payments').doc(referenceNumber);
  return store.runTransaction(async (tx) => {
    const snap = await tx.get(payRef);
    if (!snap.exists) return 'unknown';
    const payment = snap.data();
    if (payment.status === 'paid') return 'already-paid';
    tx.update(payRef, { status: 'paid', paidAt: FieldValue.serverTimestamp(), ...details });
    tx.update(store.collection('dues').doc(payment.dueId), {
      collectedTotal: FieldValue.increment(payment.amount),
      paidCount: FieldValue.increment(1),
    });
    return 'paid';
  });
}

async function markExpired(referenceNumber) {
  const store = db();
  const payRef = store.collection('payments').doc(referenceNumber);
  return store.runTransaction(async (tx) => {
    const snap = await tx.get(payRef);
    if (!snap.exists) return 'unknown';
    if (snap.data().status !== 'pending') return 'unchanged';
    tx.update(payRef, { status: 'expired' });
    return 'expired';
  });
}

module.exports = { db, markPaid, markExpired, FieldValue };
