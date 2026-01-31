import { Request, Response, NextFunction } from 'express';
import * as jose from 'jose';
import { queryOne } from '../db.js';

// Extend Express Request to include user
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        appleUserId: string;
        email?: string;
      };
    }
  }
}

// Apple's JWKS endpoint for verifying identity tokens
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
let appleJWKS: jose.JWTVerifyGetKey | null = null;

async function getAppleJWKS(): Promise<jose.JWTVerifyGetKey> {
  if (!appleJWKS) {
    appleJWKS = jose.createRemoteJWKSet(new URL(APPLE_JWKS_URL));
  }
  return appleJWKS;
}

export async function authenticateToken(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;
  const token = authHeader?.split(' ')[1]; // Bearer <token>

  if (!token) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }

  try {
    // Verify the Apple identity token
    const jwks = await getAppleJWKS();
    const { payload } = await jose.jwtVerify(token, jwks, {
      issuer: 'https://appleid.apple.com',
      audience: process.env.APPLE_CLIENT_ID,
    });

    const appleUserId = payload.sub;
    if (!appleUserId) {
      res.status(401).json({ error: 'Invalid token: no subject' });
      return;
    }

    // Look up user in database
    const user = await queryOne<{ id: string; apple_user_id: string; email: string | null }>(
      'SELECT id, apple_user_id, email FROM users WHERE apple_user_id = $1',
      [appleUserId]
    );

    if (!user) {
      res.status(401).json({ error: 'User not found. Please sign up first.' });
      return;
    }

    // Attach user to request
    req.user = {
      id: user.id,
      appleUserId: user.apple_user_id,
      email: user.email || undefined,
    };

    next();
  } catch (error) {
    console.error('Token verification failed:', error);
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}
