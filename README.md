# DuesPay

Collect departmental and association dues by bank transfer, with a live dashboard for the treasurer. Built on the Paga Collect API.

## How it works

1. A treasurer signs in and creates a due (title + amount). The app gives it a 6-character code.
2. A student enters the code, their name, matric number and phone.
3. The backend asks Paga for a one-time bank account number for that student and amount.
4. The student transfers from any bank app.
5. Paga calls the backend's webhook. The backend verifies the hash, marks the payment paid, and the treasurer's dashboard and the student's screen update instantly.

```
Flutter app ──► Vercel backend ──► Paga Collect (/paymentRequest)
     ▲               │   ▲
     │               ▼   └── Paga callback (/api/paga-webhook)
     └────────── Firestore (live updates)
```

## Why the backend is on Vercel, not Firebase

Deploying Cloud Functions needs Firebase's Blaze plan, which requires a billing card. To stay on the free Spark plan, this project uses Firebase only for Auth and Firestore, and puts the two secret-holding endpoints on Vercel's free tier. Paga keys never ship inside the app.

## Folders

- `backend/` Node functions for Vercel: `api/create-payment.js`, `api/paga-webhook.js`, helpers in `lib/`
- `lib/` Flutter app for Android, iOS and web (`lib/` source, `setup.sh` adds the platform folders)
- `firestore.rules` Firestore security rules
- `firebase.json` Firebase Hosting (web app) and rules deploy config

## Setup

### 1. Paga (do this first, it can take the longest)

1. Create a Paga Business account and open the sandbox portal: https://beta-business.paga.com
2. Copy your public key, secret key and hash (HMAC) key from the API keys page.
3. Ask Paga's team at the hackathon to confirm your sandbox account can use the Collect API.

### 2. Firebase (free Spark plan)

1. Create a project at https://console.firebase.google.com
2. Authentication → Sign-in method → enable Email/Password.
3. Firestore Database → Create database (production mode).
4. Firestore → Rules → paste `firestore.rules` → Publish.
5. Project settings → Service accounts → Generate new private key. Keep the file private.

### 3. Backend (Vercel free tier)

```bash 
cd backend
npm install
npm test            # checks the hash logic
npx vercel          # first deploy; note the URL it prints
```

In the Vercel dashboard, add the variables from `.env.example` (Settings → Environment Variables), then run `npx vercel --prod`.

For `FIREBASE_SERVICE_ACCOUNT_B64`, run `base64 -w0 serviceAccount.json` (macOS: `base64 -i serviceAccount.json`) and paste the output.

### 4. Flutter app (Android, iOS, web)

One codebase runs on all three. From the `app/` folder:

```bash
cd app
bash setup.sh                      # adds android/, ios/, web/ and Firebase settings
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android,ios,web   # creates lib/firebase_options.dart
```

Run it:

```bash
B=--dart-define=BACKEND_URL=https://your-project.vercel.app
flutter run -d chrome $B           # web
flutter run -d android $B          # Android phone or emulator (USB debugging on)
flutter run -d ios $B              # iPhone or simulator, macOS + Xcode only
```

What `setup.sh` changes for each platform:

- **Android**: adds the INTERNET permission to the main manifest. Debug builds work without it, but a release APK would fail every network call.
- **iOS**: sets the deployment target to iOS 15, which current Firebase SDKs need.
- **Web**: sets the tab title and app name to DuesPay.

**No Mac on the team?** You can't build the iOS app, but iPhone users can open the web app in Safari and use Share → Add to Home Screen. For the demo, that covers iOS.

### 5. Put the web app online (free, Firebase Hosting)

```bash
cd app
flutter build web --release \
  --dart-define=BACKEND_URL=https://your-project.vercel.app \
  --dart-define=WEB_APP_URL=https://your-project.web.app
cd ..
npm install -g firebase-tools
firebase login
firebase use --add                 # pick your Firebase project
firebase deploy --only hosting,firestore:rules
```

Your app is then live at `https://<project-id>.web.app`. Point the landing page's "Get the app" button there.

**Pay links**: with `WEB_APP_URL` set, the treasurer's "Copy pay link" button copies a link like `https://<project-id>.web.app/?code=K7M2QX`. A student taps it in the group chat and lands straight on the payment form. The web build sets this up by itself; pass the same `--dart-define` to Android and iOS builds so their links point at the web app too.

### 6. Android APK for the judges

```bash
cd app
flutter build apk --release --dart-define=BACKEND_URL=https://your-project.vercel.app \
  --dart-define=WEB_APP_URL=https://your-project.web.app
# file: build/app/outputs/flutter-apk/app-release.apk
```

It's signed with the debug key, which is fine for sideloading a demo but not for the Play Store.

### Troubleshooting

- **Android "minSdk" error**: open `android/app/build.gradle.kts` and set `minSdk = 23`.
- **iOS "higher minimum deployment target" from CocoaPods**: rerun `bash setup.sh`, then `cd ios && pod install --repo-update`.
- **Web sign-in fails with "unauthorized domain"**: Firebase console → Authentication → Settings → Authorized domains → add your hosting domain. `web.app` and `localhost` are already there.

## Test it end to end

1. Treasurer: create an account, create a due for ₦100, copy the code.
2. Student (second phone or after going back): enter the code and details.
3. Pay the account number using Paga's sandbox, or simulate the callback (below).
4. Watch both screens flip to paid.

Simulate a callback while you wait for sandbox access:

```bash
REF=DP...            # referenceNumber from the payments collection
KEY=your_hash_key
HASH=$(printf '%s' "n1" "0" "$REF" "CONSUMED" "0.00" "$KEY" | sha512sum | cut -d' ' -f1)
curl -X POST https://your-project.vercel.app/api/paga-webhook \
  -H 'Content-Type: application/json' \
  -d "{\"event\":\"PAYMENT_COMPLETE\",\"notificationId\":\"n1\",\"statusCode\":\"0\",\"externalReferenceNumber\":\"$REF\",\"state\":\"CONSUMED\",\"outstandingBalance\":0,\"paymentAmount\":100,\"hash\":\"$HASH\"}"
```

## Things to verify with Paga

The integration follows Paga's public docs, which are inconsistent in places. Check these on your first sandbox call:

- **Request hash**: SHA-512 of `referenceNumber + amount + currency + payer.phoneNumber + payer.email + payee.* + hashKey`, blanks skipped (`lib/paga.js`).
- **Callback hash**: SHA-512 of `notificationId + statusCode + externalReferenceNumber + state + outstandingBalance(2dp) + hashKey`. If real callbacks get a 401, compare against a logged payload.
- **Fee shares**: Paga's sample sends payer 1.0 / payee 0.0, but the field description says the total must be under 1.0. Change `PAYER_FEE_SHARE` / `PAYEE_FEE_SHARE` if the request is rejected.
- **Account number field**: read from `paymentMethods[].properties.AccountNumber`.

## Known limits (fine for a demo, fix before real use)

- `create-payment` has no rate limit or sign-in.
- A student can create more than one pending payment for the same due.
- No payout screen yet; collected money sits in the Paga business account.

## Stretch goals

- Export paid list as CSV.
- "Withdraw to bank" using Paga's Business API (needs a static IP whitelisted by Paga for live debits).
- Push a notification to the treasurer's phone on every payment.
