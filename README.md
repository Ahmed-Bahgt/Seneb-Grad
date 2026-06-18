# tamren_tech

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
"# Grad_tamrenaTech" 

## Password Reset via 6-digit OTP (External Backend)

This project supports password reset with a 6-digit code sent directly in email text.

### Backend location

- backend/password-reset-api

### Run backend locally

1. Open backend/password-reset-api
2. Copy .env.example to .env
3. Fill Firebase Admin and SMTP values
4. Install dependencies: npm install
5. Start server: npm start

### Connect Flutter app to backend

Run Flutter with API base URL:

flutter run --dart-define=PASSWORD_RESET_API_BASE_URL=http://YOUR_HOST:8787

### Flow

1. User enters account email in Forgot Password screen.
2. Backend generates 6-digit OTP and sends it to email as plain text.
3. User enters OTP + new password in app.
4. Backend verifies OTP, updates Firebase Auth password, and revokes old sessions.

### Security behavior

- OTP expires after 10 minutes
- Max invalid attempts per code: 5
- Resend cooldown: 60 seconds
- Max code requests per hour per email: 5
