import { useMemo } from 'react';
import { cognitoHostedUILoginUrl } from '../config/amplify';

export const LoginPage = () => {
  const loginUrl = useMemo(() => cognitoHostedUILoginUrl, []);

  return (
    <section className="card">
      <h2>Sign in to HMS</h2>
      <p>Authentication is handled via Amazon Cognito Hosted UI.</p>
      <a className="button" href={loginUrl}>
        Continue to Secure Login
      </a>
    </section>
  );
};
