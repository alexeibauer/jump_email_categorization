# Google OAuth Setup Guide

This guide explains how to set up Google OAuth for Gmail integration in your application.

## Overview

The app now supports Google OAuth authentication to connect Gmail accounts. When users click "Add Gmail Account", they'll be redirected to Google's OAuth consent screen to authorize access to their Gmail.

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" at the top
3. Click "NEW PROJECT"
4. Enter project name: "Jump Email Categorization" (or your preferred name)
5. Click "CREATE"

## Step 2: Enable Gmail API

1. In your Google Cloud Project, go to "APIs & Services" > "Library"
2. Search for "Gmail API"
3. Click on "Gmail API"
4. Click "ENABLE"

## Step 3: Configure OAuth Consent Screen

1. Go to "APIs & Services" > "OAuth consent screen"
2. Choose "External" user type (unless you have a Google Workspace account)
3. Click "CREATE"

### Fill in the OAuth consent screen:

**App information:**
- App name: `Jump Email Categorization`
- User support email: Your email address
- App logo: (Optional) Upload your app logo

**App domain:**
- Application home page: `http://localhost:4000` (for development)
- Application privacy policy link: (Optional) Add if you have one
- Application terms of service link: (Optional) Add if you have one

**Authorized domains:**
- For development: Leave empty or add `localhost`
- For production: Add your domain (e.g., `yourdomain.com`)

**Developer contact information:**
- Email addresses: Your email address

4. Click "SAVE AND CONTINUE"

### Scopes:

1. Click "ADD OR REMOVE SCOPES"
2. Add these scopes:
   - `.../auth/userinfo.email` - View your email address
   - `.../auth/userinfo.profile` - See your personal info
   - `.../auth/gmail.readonly` - View your email messages and settings (Read-only)
   - `.../auth/gmail.labels` - For the app to be able to archive emails
3. Click "UPDATE"
4. Click "SAVE AND CONTINUE"

### Test users (for development):

1. Click "ADD USERS"
2. Add your email address and any other test users
3. Click "ADD"
4. Click "SAVE AND CONTINUE"

## Step 4: Create OAuth Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "CREATE CREDENTIALS" > "OAuth client ID"
3. Choose "Web application"

### Configure the OAuth client:

**Name:** `Jump Email Categorization Web Client`

**Authorized JavaScript origins:**
- For development: `http://localhost:4000`
- For production: `https://yourdomain.com`

**Authorized redirect URIs:**
- For development: `http://localhost:4000/auth/google/callback`
- For production: `https://yourdomain.com/auth/google/callback`

4. Click "CREATE"
5. A dialog will show your **Client ID** and **Client Secret**
6. **IMPORTANT**: Copy both values immediately!

## Step 5: Configure Your Application

### Set Environment Variables

Create a `.env` file in your project root (or add to your existing one):

```bash
# Google OAuth Credentials
export GOOGLE_CLIENT_ID="your-client-id-here.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="your-client-secret-here"
```

### Load Environment Variables

Before starting your Phoenix server, load the environment variables:

```bash
source .env
mix phx.server
```

**Or** for permanent setup, add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export GOOGLE_CLIENT_ID="your-client-id-here"
export GOOGLE_CLIENT_SECRET="your-client-secret-here"
```

Then reload your shell:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

## Step 6: Test the OAuth Flow

1. Start your Phoenix server: `mix phx.server`
2. Navigate to `http://localhost:4000`
3. Log in with your user account
4. Click "Add Gmail Account" in the left sidebar
5. You should be redirected to Google's OAuth consent screen
6. Select your Google account
7. Review and accept the permissions
8. You'll be redirected back to your app
9. The Gmail account should now appear in the left sidebar!

## Troubleshooting

### "Error 400: redirect_uri_mismatch"
- Make sure the redirect URI in Google Cloud Console exactly matches: `http://localhost:4000/auth/google/callback`
- No trailing slashes
- Check for typos

### "Access blocked: This app's request is invalid"
- Make sure you've added your email as a test user in the OAuth consent screen
- The app must be in "Testing" status to work with external users

### OAuth not working
- Verify environment variables are set: `echo $GOOGLE_CLIENT_ID`
- Check that you've loaded the `.env` file before starting the server
- Look at server logs for error messages

### "Invalid credentials" error
- Double-check your Client ID and Client Secret
- Make sure there are no extra spaces or quotes when copying

## Production Deployment

For production:

1. Update OAuth consent screen status from "Testing" to "In Production" (requires verification for certain scopes)
2. Add your production domain to:
   - Authorized JavaScript origins: `https://yourdomain.com`
   - Authorized redirect URIs: `https://yourdomain.com/auth/google/callback`
3. Set environment variables on your production server
4. Use a secrets management service (like Google Secret Manager, AWS Secrets Manager, etc.)

## Security Notes

- **Never commit** your `.env` file or expose your Client Secret
- Add `.env` to your `.gitignore` file
- Use environment variables or a secrets manager for production
- The `refresh_token` is only provided on the first authorization - store it securely
- Access tokens expire after 1 hour - implement token refresh logic

## Useful Links

- [Google OAuth 2.0 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Ueberauth Google Strategy](https://github.com/ueberauth/ueberauth_google)

