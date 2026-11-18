# DuesPay

**Simplifying departmental and association dues collection through bank transfers.**

DuesPay is a digital dues collection platform that helps student associations, departments, and organizations collect payments without manually tracking bank transfers. Built with Flutter, Firebase, Vercel, and the Paga Collect API, it provides unique payment codes, dedicated virtual accounts, and real-time collection tracking.

## How It Works

1. **Create a due:** A treasurer signs in, creates a collection with a title and amount, and receives a unique six-character payment code.
2. **Student registration:** A student enters the payment code alongside their name, matriculation number, and phone number.
3. **Generate a payment account:** The backend requests a one-time virtual account from Paga for the student and specified amount.
4. **Make payment:** The student transfers the required amount using any supported banking application.
5. **Payment confirmation:** Paga sends a callback to the backend. The backend validates the callback hash, processes the payment, and updates the payment record.
6. **Real-time tracking:** Firestore synchronizes the payment status across the student's payment screen and the treasurer's dashboard.

## System Architecture

```text
              Flutter Application
                 (Android/iOS/Web)
                        |
                        ▼
                 Vercel Backend
                   Node.js API
                        |
             ┌──────────┴──────────┐
             ▼                     ▼
        Paga Collect           Firebase
        Payment API          Authentication
             ▲                 Firestore
             │                     ▲
             │                     │
        Paga Webhook ──────────────┘
        (/api/paga-webhook)
```

### Technology Stack

| Component | Technology |
|---|---|
| Mobile and web frontend | Flutter / Dart |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore |
| Backend | Node.js / Vercel Functions |
| Payment processing | Paga Collect API |
| Web hosting | Firebase Hosting |
| Backend hosting | Vercel |

## Why Vercel Instead of Firebase Cloud Functions?

DuesPay uses Firebase's free Spark plan for authentication and Firestore.

Deploying Firebase Cloud Functions requires upgrading to the Blaze plan, which requires a billing account.

To avoid this requirement, DuesPay uses Vercel's free tier to host its backend API endpoints.

This architecture separates frontend services from payment processing:

- Firebase handles authentication and real-time database updates.
- Vercel handles backend requests and payment callbacks.
- Paga handles virtual account generation and bank transfer processing.
- Secret API credentials remain on the backend and are never embedded in the Flutter application.

## Project Structure

```text
duespay/
│
├── backend/
│   ├── api/
│   │   ├── create-payment.js
│   │   └── paga-webhook.js
│   │
│   ├── lib/
│   │   ├── firebase.js
│   │   └── paga.js
│   │
│   ├── test/
│   └── package.json
│
├── lib/
│   ├── screens/
│   │   ├── pay.dart
│   │   └── treasurer.dart
│   └── main.dart
│
├── android/
├── ios/
├── web/
├── macos/
├── linux/
├── windows/
│
├── firestore.rules
├── firestore.indexes.json
├── firebase.json
├── setup.sh
├── pubspec.yaml
└── README.md
```

The Flutter application lives in the root `lib/` directory. The backend is maintained separately in `backend/`.

## Getting Started

### Prerequisites

- Flutter SDK
- Dart SDK
- Node.js and npm
- Firebase account
- Vercel account
- Paga Business account with Collect API access

### 1. Configure Paga

Paga integration is required for generating virtual collection accounts and receiving payment notifications.

1. Create a Paga Business account.
2. Access the Paga sandbox portal: https://beta-business.paga.com
3. Obtain your API public key, secret key, and HMAC hash key.
4. Contact Paga's technical team to confirm that your sandbox account has access to the Collect API.

Keep all credentials private. They must only be configured on the backend.

### 2. Configure Firebase

Create a Firebase project at https://console.firebase.google.com.

Configure the following:

1. Enable Email/Password authentication.
2. Create a Cloud Firestore database in production mode.
3. Deploy the security rules from `firestore.rules`.
4. Open Project Settings → Service Accounts.
5. Generate a Firebase Admin SDK service account key.

Keep the generated service account JSON private. Never commit it to Git.

### 3. Deploy the Backend to Vercel

Navigate to the backend directory:

```bash
cd backend
npm install
npm test
npx vercel
```

Follow the prompts to link your project to Vercel.

After the initial deployment:

1. Open your Vercel project dashboard.
2. Navigate to Settings → Environment Variables.
3. Configure the environment variables listed in `.env.example`.
4. Deploy the production version:

```bash
npx vercel --prod
```

For the Firebase service account, encode your JSON credentials as Base64:

**macOS:**

```bash
base64 -i serviceAccount.json
```

Use the output as the value for `FIREBASE_SERVICE_ACCOUNT_B64`.

Do not commit `.env` files or service account credentials.

### 4. Configure the Flutter Application

The Flutter application is located in the project root.

From the DuesPay root directory, run:

```bash
flutter pub get

bash setup.sh
```

Install FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
```

Configure Firebase for the supported platforms:

```bash
flutterfire configure --platforms=android,ios,web
```

This generates `lib/firebase_options.dart`.

### 5. Run the Application

Replace the backend URL with your deployed Vercel URL.

**Web:**

```bash
flutter run -d chrome \
  --dart-define=BACKEND_URL=https://your-project.vercel.app
```

**Android:**

```bash
flutter run -d android \
  --dart-define=BACKEND_URL=https://your-project.vercel.app
```

**iOS:**

```bash
flutter run -d ios \
  --dart-define=BACKEND_URL=https://your-project.vercel.app
```

For iOS development, macOS and Xcode are required.

### 6. Deploy the Web Application

Build the Flutter web application:

```bash
flutter build web --release \
  --dart-define=BACKEND_URL=https://your-project.vercel.app \
  --dart-define=WEB_APP_URL=https://your-project.web.app
```

Install Firebase CLI:

```bash
npm install -g firebase-tools
```

Authenticate and select your Firebase project:

```bash
firebase login
firebase use --add
```

Deploy the web application and Firestore rules:

```bash
firebase deploy --only hosting,firestore:rules
```

Your application will be available at:

```text
https://your-project.web.app
```

### Payment Links

DuesPay supports shareable payment links.

When `WEB_APP_URL` is configured, a treasurer can copy a payment link containing the due code.

Example:

```text
https://your-project.web.app/?code=K7M2QX
```

Students can open the link directly from WhatsApp, Telegram, or other messaging platforms and proceed to the payment form.

Use the same `WEB_APP_URL` when building Android and iOS applications so generated payment links point to the web application.

### 7. Build the Android APK

Generate a release APK:

```bash
flutter build apk --release \
  --dart-define=BACKEND_URL=https://your-project.vercel.app \
  --dart-define=WEB_APP_URL=https://your-project.web.app
```

Generated APK:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The default debug signing configuration is suitable for demo sideloading but must be replaced with a proper release signing configuration before Play Store distribution.

## Testing the Payment Flow

You can test DuesPay using two separate sessions.

**Treasurer:**

1. Create an account.
2. Sign in.
3. Create a new due with an amount of ₦100.
4. Copy the generated six-character payment code.

**Student:**

1. Open DuesPay in another browser or device.
2. Enter the payment code.
3. Provide your name, matriculation number, and phone number.
4. Generate a virtual account.
5. Transfer the required amount through the Paga sandbox.

**Verification:**

Once Paga confirms the transaction:

- The backend processes the webhook.
- The payment record is updated.
- The student's payment status changes.
- The treasurer's collection totals update through Firestore.

### Simulating a Paga Webhook

If sandbox payment access is unavailable, you can simulate a callback for testing.

```bash
REF=DP... 
KEY=your_hash_key

HASH=$(printf '%s' "n1" "0" "$REF" "CONSUMED" "0.00" "$KEY" \
  | shasum -a 512 | cut -d' ' -f1)

curl -X POST https://your-project.vercel.app/api/paga-webhook \
  -H 'Content-Type: application/json' \
  -d "{\"event\":\"PAYMENT_COMPLETE\",\"notificationId\":\"n1\",\"statusCode\":\"0\",\"externalReferenceNumber\":\"$REF\",\"state\":\"CONSUMED\",\"outstandingBalance\":0,\"paymentAmount\":100,\"hash\":\"$HASH\"}"
```

Use a valid payment reference from your test environment. The webhook must validate the hash and transaction details before updating Firestore.

## Paga Integration: Important Verification Points

Paga's public API documentation has some inconsistencies. Verify the following during your first sandbox transaction.

**1. Request hash**

The integration currently uses SHA-512 based on:

`referenceNumber + amount + currency + payer.phoneNumber + payer.email + payee.* + hashKey`

Empty values are skipped.

Implementation: `backend/lib/paga.js`.

**2. Callback hash**

The expected callback hash is based on:

`notificationId + statusCode + externalReferenceNumber + state + outstandingBalance(2dp) + hashKey`

If Paga returns HTTP 401, inspect the actual callback payload and compare the hash-generation logic against Paga's confirmed specification.

**3. Fee shares**

Paga's examples and field descriptions may differ regarding payer and payee fee shares.

Verify the accepted values before changing `PAYER_FEE_SHARE` and `PAYEE_FEE_SHARE`.

**4. Virtual account number**

The generated account number is retrieved from:

`paymentMethods[].properties.AccountNumber`

Confirm the actual response structure against the sandbox API response.

## Known Limitations

The current implementation is designed for a working demonstration. The following areas require additional hardening before production deployment:

- Payment creation needs authentication and rate limiting.
- Duplicate pending payment requests should be restricted.
- Webhook processing should be idempotent to prevent duplicate collection totals.
- Payment amounts and references must be verified against the original transaction request.
- Payment status changes must only be authorized through trusted backend verification.
- A payout and settlement interface has not yet been implemented.
- Collected funds remain in the Paga Business account until withdrawn or settled through the appropriate Paga process.

## Future Improvements

Potential additions to the DuesPay roadmap include:

- **CSV Export:** Allow treasurers to export payment records and student lists.
- **Automated Notifications:** Send real-time payment notifications to treasurers.
- **Payment Analytics:** Provide collection summaries, outstanding balances, and payment statistics.
- **Bank Withdrawals:** Integrate Paga's Business API for supported withdrawals.
- **Multiple Collection Categories:** Support different dues, levies, departmental fees, and association contributions.
- **Payment Reconciliation:** Provide transaction references and downloadable payment reports.

## License

Add your preferred open-source license before publishing the repository.