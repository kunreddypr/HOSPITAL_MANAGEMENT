import { Amplify } from 'aws-amplify';
import type { AppRuntimeConfig } from '../types/global';

const runtimeConfig: AppRuntimeConfig | undefined = typeof window !== 'undefined' ? window.__APP_CONFIG__ : undefined;

const fallbackApiBaseUrl = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://localhost:8080';
const userPoolId = runtimeConfig?.cognito.userPoolId ?? (import.meta.env.VITE_COGNITO_USER_POOL_ID as string);
const clientId = runtimeConfig?.cognito.clientId ?? (import.meta.env.VITE_COGNITO_CLIENT_ID as string);
const region = runtimeConfig?.region ?? (import.meta.env.VITE_REGION as string);
const domain = runtimeConfig?.cognito.domain ?? (import.meta.env.VITE_COGNITO_DOMAIN as string);
const apiBaseUrl = runtimeConfig?.apiBaseUrl ?? fallbackApiBaseUrl;

Amplify.configure({
  Auth: {
    mandatorySignIn: true,
    region,
    userPoolId,
    userPoolWebClientId: clientId,
    oauth: {
      domain: domain.replace(/^https?:\/\//, ''),
      scope: ['email', 'openid', 'profile'],
      redirectSignIn: window.location.origin,
      redirectSignOut: window.location.origin,
      responseType: 'code'
    }
  }
});

export const cognitoHostedUILoginUrl = `${domain}/login?client_id=${clientId}&response_type=code&scope=openid+profile+email&redirect_uri=${encodeURIComponent(window.location.origin)}`;

export const runtimeApiBaseUrl = apiBaseUrl;
