import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import { createRecallApi } from './http.js';
import { RecallStore } from './store.js';
initializeApp();
const auth = getAuth();
const store = new RecallStore(getFirestore(), Date.now, { allowSandbox: () => process.env.RECALL_ALLOW_SANDBOX_BILLING === '1' });
const aiEnabled = process.env.RECALL_AI_ENABLED === '1';
const billingEnabled = process.env.RECALL_BILLING_ENABLED === '1';
const secretBindings: string[] = [];
if (aiEnabled) secretBindings.push('OPENAI_API_KEY');
if (billingEnabled) secretBindings.push('REVENUECAT_SECRET_API_KEY', 'REVENUECAT_WEBHOOK_AUTH');
const handler = createRecallApi({
  store,
  verifyToken: token => auth.verifyIdToken(token, true),
  deleteUser: uid => auth.deleteUser(uid),
  userExists: async uid => {
    try { await auth.getUser(uid); return true; }
    catch (error) {
      if ((error as { code?: string }).code === 'auth/user-not-found') return false;
      throw error;
    }
  },
  env: name => {
    if (name === 'APP_ORIGIN') return process.env.APP_ORIGIN ?? `https://${process.env.GCLOUD_PROJECT ?? 'recall-f1d1e'}.web.app`;
    if (name === 'RECALL_AI_ENABLED') return aiEnabled ? '1' : '0';
    if (name.startsWith('REVENUECAT_') && !billingEnabled) return undefined;
    return process.env[name];
  },
});
export const recallApi = onRequest({ region: 'europe-west1', serviceAccount: 'recall-api@recall-f1d1e.iam.gserviceaccount.com', memory: '512MiB', timeoutSeconds: 120, maxInstances: 2, minInstances: 0, concurrency: 1, cors: false, invoker: 'public', secrets: secretBindings }, handler);
