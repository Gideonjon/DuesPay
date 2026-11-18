
'use strict';

const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

function db() {
  if (!getApps().length) {
    const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;

    if (!b64) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT_B64 is not set.');
    }

    const serviceAccount = JSON.parse(
      Buffer.from(b64, 'base64').toString('utf8')
    );

    initializeApp({
      credential: cert(serviceAccount),
    });
  }

  return getFirestore();
}

async function markPaid(referenceNumber, details = {}) {
  if (
    typeof referenceNumber !== 'string' ||
    !referenceNumber.trim()
  ) {
    throw new Error('A valid payment reference is required.');
  }

  const store = db();
  const payRef = store.collection('payments').doc(referenceNumber);

  return store.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(payRef);

    if (!paymentSnap.exists) {
      return 'unknown';
    }

    const payment = paymentSnap.data();

    if (payment.status === 'paid') {
      return 'already-paid';
    }

    if (
      !payment.dueId ||
      typeof payment.amount !== 'number' ||
      !Number.isFinite(payment.amount) ||
      payment.amount <= 0
    ) {
      throw new Error('Payment record has invalid due or amount.');
    }

    const dueRef = store.collection('dues').doc(payment.dueId);
    const dueSnap = await tx.get(dueRef);

    if (!dueSnap.exists) {
      throw new Error(`Due ${payment.dueId} does not exist.`);
    }

    tx.update(payRef, {
      status: 'paid',
      paidAt: FieldValue.serverTimestamp(),
      ...details,
    });

    tx.update(dueRef, {
      collectedTotal: FieldValue.increment(payment.amount),
      paidCount: FieldValue.increment(1),
    });

    return 'paid';
  });
}

async function markExpired(referenceNumber) {
  if (
    typeof referenceNumber !== 'string' ||
    !referenceNumber.trim()
  ) {
    throw new Error('A valid payment reference is required.');
  }

  const store = db();
  const payRef = store.collection('payments').doc(referenceNumber);

  return store.runTransaction(async (tx) => {
    const snap = await tx.get(payRef);

    if (!snap.exists) {
      return 'unknown';
    }

    if (snap.data().status !== 'pending') {
      return 'unchanged';
    }

    tx.update(payRef, {
      status: 'expired',
      expiredAt: FieldValue.serverTimestamp(),
    });

    return 'expired';
  });
}

module.exports = {
  db,
  markPaid,
  markExpired,
  FieldValue,
};
