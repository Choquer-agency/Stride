import { Router } from 'express';
import * as jose from 'jose';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, execute } from '../db.js';

export const authRouter = Router();

// Apple's JWKS endpoint
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
let appleJWKS: jose.JWTVerifyGetKey | null = null;

async function getAppleJWKS(): Promise<jose.JWTVerifyGetKey> {
  if (!appleJWKS) {
    appleJWKS = jose.createRemoteJWKSet(new URL(APPLE_JWKS_URL));
  }
  return appleJWKS;
}

interface SignInRequest {
  identityToken: string;
  authorizationCode: string;
  email?: string;
  fullName?: {
    givenName?: string;
    familyName?: string;
  };
}

// Sign in or sign up with Apple
authRouter.post('/apple', async (req, res) => {
  try {
    const { identityToken, email, fullName } = req.body as SignInRequest;

    if (!identityToken) {
      res.status(400).json({ error: 'Identity token required' });
      return;
    }

    // Verify the Apple identity token
    const jwks = await getAppleJWKS();
    const { payload } = await jose.jwtVerify(identityToken, jwks, {
      issuer: 'https://appleid.apple.com',
      audience: process.env.APPLE_CLIENT_ID,
    });

    const appleUserId = payload.sub;
    if (!appleUserId) {
      res.status(400).json({ error: 'Invalid token: no subject' });
      return;
    }

    // Check if user exists
    let user = await queryOne<{
      id: string;
      apple_user_id: string;
      email: string | null;
      display_name: string | null;
      created_at: string;
    }>(
      'SELECT id, apple_user_id, email, display_name, created_at FROM users WHERE apple_user_id = $1',
      [appleUserId]
    );

    if (user) {
      // Existing user - return their info
      res.json({
        user: {
          id: user.id,
          email: user.email,
          displayName: user.display_name,
          createdAt: user.created_at,
        },
        isNewUser: false,
      });
    } else {
      // New user - create account
      const userId = uuidv4();
      const displayName = fullName
        ? [fullName.givenName, fullName.familyName].filter(Boolean).join(' ')
        : null;

      await execute(
        `INSERT INTO users (id, apple_user_id, email, display_name, created_at)
         VALUES ($1, $2, $3, $4, NOW())`,
        [userId, appleUserId, email || null, displayName]
      );

      // Create default training preferences
      await execute(
        `INSERT INTO training_preferences (id, user_id, weekly_run_days, weekly_gym_days)
         VALUES ($1, $2, 4, 2)`,
        [uuidv4(), userId]
      );

      // Create default user profile
      await execute(
        `INSERT INTO user_profiles (id, user_id, available_equipment)
         VALUES ($1, $2, ARRAY['none', 'dumbbells', 'resistance_bands'])`,
        [uuidv4(), userId]
      );

      res.status(201).json({
        user: {
          id: userId,
          email: email || null,
          displayName,
          createdAt: new Date().toISOString(),
        },
        isNewUser: true,
      });
    }
  } catch (error) {
    console.error('Apple sign-in error:', error);
    res.status(500).json({ error: 'Authentication failed' });
  }
});

// Get current user info
authRouter.get('/me', async (req, res) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.split(' ')[1];

  if (!token) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }

  try {
    const jwks = await getAppleJWKS();
    const { payload } = await jose.jwtVerify(token, jwks, {
      issuer: 'https://appleid.apple.com',
      audience: process.env.APPLE_CLIENT_ID,
    });

    const appleUserId = payload.sub;
    const user = await queryOne<{
      id: string;
      email: string | null;
      display_name: string | null;
      created_at: string;
    }>(
      'SELECT id, email, display_name, created_at FROM users WHERE apple_user_id = $1',
      [appleUserId]
    );

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    res.json({
      id: user.id,
      email: user.email,
      displayName: user.display_name,
      createdAt: user.created_at,
    });
  } catch (error) {
    res.status(401).json({ error: 'Invalid token' });
  }
});

// Delete account
authRouter.delete('/account', async (req, res) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.split(' ')[1];

  if (!token) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }

  try {
    const jwks = await getAppleJWKS();
    const { payload } = await jose.jwtVerify(token, jwks, {
      issuer: 'https://appleid.apple.com',
      audience: process.env.APPLE_CLIENT_ID,
    });

    const appleUserId = payload.sub;

    // Delete user (cascade will delete all related data)
    await execute('DELETE FROM users WHERE apple_user_id = $1', [appleUserId]);

    res.json({ message: 'Account deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete account' });
  }
});
