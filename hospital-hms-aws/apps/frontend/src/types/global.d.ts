export interface AppRuntimeConfig {
  apiBaseUrl: string;
  region: string;
  cognito: {
    userPoolId: string;
    clientId: string;
    domain: string;
  };
}

declare global {
  interface Window {
    __APP_CONFIG__?: AppRuntimeConfig;
  }
}

export {};
