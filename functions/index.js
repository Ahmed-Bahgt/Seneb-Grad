const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

admin.initializeApp();

const db = admin.firestore();

const OTP_LENGTH = 6;
const OTP_EXPIRE_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;
const COOLDOWN_SECONDS = 60;
const MAX_REQUESTS_PER_HOUR = 5;

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function resetDocId(email) {
  return crypto.createHash('sha256').update(email).digest('hex');
}

function randomOtp() {
  const min = 10 ** (OTP_LENGTH - 1);
  const max = (10 ** OTP_LENGTH) - 1;
  return String(Math.floor(Math.random() * (max - min + 1)) + min);
}

function hashOtp(email, otp) {
  return crypto
    .createHash('sha256')
    .update(`${email}:${otp}`)
    .digest('hex');
}

function buildTransporter() {
  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT || 587);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!host || !user || !pass) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'SMTP is not configured. Set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS.'
    );
  }

  return nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });
}

async function sendOtpEmail({ to, code }) {
  const from = process.env.SMTP_FROM || process.env.SMTP_USER;
  const appName = process.env.APP_NAME || 'Tamren Tech';
  const transporter = buildTransporter();

  await transporter.sendMail({
    from,
    to,
    subject: `${appName} - Password Reset Code`,
    text: `Your password reset code is: ${code}\n\nThis code expires in ${OTP_EXPIRE_MINUTES} minutes.`,
    html: `
      <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #111;">
        <h2 style="margin-bottom: 8px;">${appName}</h2>
        <p>Your password reset code is:</p>
        <div style="font-size: 28px; font-weight: 700; letter-spacing: 6px; margin: 16px 0;">${code}</div>
        <p>This code expires in <b>${OTP_EXPIRE_MINUTES} minutes</b>.</p>
        <p>If you did not request this, you can ignore this email.</p>
      </div>
    `,
  });
}

exports.sendPasswordResetCode = functions.https.onCall(async (data) => {
  const email = normalizeEmail(data?.email);

  if (!email || !email.includes('@')) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid email.');
  }

  // Do not leak user existence.
  let userRecord = null;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (_) {
    return { success: true };
  }

  if (!userRecord) {
    return { success: true };
  }

  const docRef = db.collection('password_reset_codes').doc(resetDocId(email));
  const now = Date.now();

  const snap = await docRef.get();
  const oldData = snap.data() || {};

  const recentRequests = Array.isArray(oldData.requestTimesMs)
    ? oldData.requestTimesMs.filter((t) => Number.isFinite(t) && now - t < 60 * 60 * 1000)
    : [];

  const lastSentAtMs = Number(oldData.lastSentAtMs || 0);
  if (lastSentAtMs > 0 && now - lastSentAtMs < COOLDOWN_SECONDS * 1000) {
    const waitSec = Math.ceil((COOLDOWN_SECONDS * 1000 - (now - lastSentAtMs)) / 1000);
    throw new functions.https.HttpsError(
      'resource-exhausted',
      `Please wait ${waitSec} seconds before requesting another code.`
    );
  }

  if (recentRequests.length >= MAX_REQUESTS_PER_HOUR) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'Too many reset requests for this email. Please try again later.'
    );
  }

  const otp = randomOtp();
  const expiresAtMs = now + OTP_EXPIRE_MINUTES * 60 * 1000;
  const codeHash = hashOtp(email, otp);

  await sendOtpEmail({ to: email, code: otp });

  recentRequests.push(now);

  await docRef.set(
    {
      email,
      codeHash,
      attempts: 0,
      maxAttempts: OTP_MAX_ATTEMPTS,
      expiresAtMs,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSentAtMs: now,
      requestTimesMs: recentRequests,
    },
    { merge: true }
  );

  return {
    success: true,
    expiresInMinutes: OTP_EXPIRE_MINUTES,
  };
});

exports.confirmPasswordResetWithCode = functions.https.onCall(async (data) => {
  const email = normalizeEmail(data?.email);
  const code = String(data?.code || '').trim();
  const newPassword = String(data?.newPassword || '');

  if (!email || !email.includes('@')) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid email.');
  }

  if (!code || !/^\d{6}$/.test(code)) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid reset code.');
  }

  if (newPassword.length < 8) {
    throw new functions.https.HttpsError('invalid-argument', 'Password is too weak.');
  }

  const docRef = db.collection('password_reset_codes').doc(resetDocId(email));
  const snap = await docRef.get();

  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'No reset code found for this email.');
  }

  const payload = snap.data() || {};
  const now = Date.now();

  const expiresAtMs = Number(payload.expiresAtMs || 0);
  if (!expiresAtMs || now > expiresAtMs) {
    await docRef.delete();
    throw new functions.https.HttpsError('deadline-exceeded', 'Reset code expired.');
  }

  const attempts = Number(payload.attempts || 0);
  const maxAttempts = Number(payload.maxAttempts || OTP_MAX_ATTEMPTS);
  if (attempts >= maxAttempts) {
    await docRef.delete();
    throw new functions.https.HttpsError('permission-denied', 'Too many invalid attempts.');
  }

  const expectedHash = String(payload.codeHash || '');
  const submittedHash = hashOtp(email, code);

  if (!expectedHash || expectedHash !== submittedHash) {
    await docRef.update({
      attempts: attempts + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new functions.https.HttpsError('invalid-argument', 'Invalid reset code.');
  }

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (_) {
    throw new functions.https.HttpsError('not-found', 'Account not found.');
  }

  await admin.auth().updateUser(userRecord.uid, {
    password: newPassword,
  });

  await admin.auth().revokeRefreshTokens(userRecord.uid);
  await docRef.delete();

  return { success: true };
});
