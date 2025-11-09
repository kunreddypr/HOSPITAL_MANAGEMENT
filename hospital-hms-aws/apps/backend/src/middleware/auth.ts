import { Request, Response, NextFunction } from 'express';
import jwt, { JwtHeader, SigningKeyCallback } from 'jsonwebtoken';
import jwksRsa from 'jwks-rsa';

const jwksUrl = process.env.COGNITO_JWKS_URL;
const audience = process.env.COGNITO_CLIENT_ID;
const issuer = process.env.COGNITO_USER_POOL_ID
  ? `https://cognito-idp.${process.env.AWS_REGION}.amazonaws.com/${process.env.COGNITO_USER_POOL_ID}`
  : undefined;

if (!jwksUrl) {
  throw new Error('COGNITO_JWKS_URL must be set');
}

const client = jwksRsa({
  cache: true,
  rateLimit: true,
  jwksUri: jwksUrl
});

function getKey(header: JwtHeader, callback: SigningKeyCallback) {
  client.getSigningKey(header.kid as string, (err, key) => {
    if (err) {
      callback(err, undefined);
      return;
    }
    const signingKey = key?.getPublicKey();
    callback(null, signingKey);
  });
}

export function authMiddleware(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Missing Authorization header' });
  }

  const token = authHeader.substring('Bearer '.length);

  jwt.verify(
    token,
    getKey,
    {
      audience,
      issuer,
      algorithms: ['RS256']
    },
    (err, decoded) => {
      if (err || typeof decoded !== 'object' || decoded === null) {
        return res.status(401).json({ message: 'Invalid token' });
      }

      req.user = decoded as typeof req.user;
      next();
    }
  );
}
