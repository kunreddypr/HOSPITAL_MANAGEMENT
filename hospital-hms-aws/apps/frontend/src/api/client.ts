import { fetchAuthSession } from 'aws-amplify/auth';
import { runtimeApiBaseUrl } from '../config/amplify';

const baseUrl = runtimeApiBaseUrl;

async function getAuthHeader(): Promise<Record<string, string>> {
  const session = await fetchAuthSession();
  const token = session.tokens?.idToken?.toString() ?? session.tokens?.accessToken?.toString();

  if (!token) {
    throw new Error('No Cognito tokens available. Ensure the user is authenticated.');
  }

  return {
    Authorization: `Bearer ${token}`
  };
}

export async function apiGet<T>(path: string): Promise<T> {
  const headers = await getAuthHeader();
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'GET',
    headers
  });

  if (!response.ok) {
    throw new Error(`API GET ${path} failed with status ${response.status}`);
  }

  return response.json() as Promise<T>;
}

export async function apiPost<T, B = unknown>(path: string, body: B): Promise<T> {
  const headers = await getAuthHeader();
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...headers
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`API POST ${path} failed with status ${response.status}: ${errorText}`);
  }

  return response.json() as Promise<T>;
}
