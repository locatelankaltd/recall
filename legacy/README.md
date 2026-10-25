# Earlier backend implementations

These folders are historical development references. They are not part of the
Firebase app runtime or deployment.

- `supabase`: the undeployed SQL and Edge Functions implementation from Recall
  0.2, including its original tests.
- `service`: the earlier loopback-only Python recipient-review prototype.

The active backend is [`functions`](../functions), with Firestore security rules
at the project root. Flutter uses Firebase Authentication and the Recall HTTPS
API. See [ADR-002](../docs/ADR-002-firebase.md) and the
[Firebase deployment record](../docs/FIREBASE_DEPLOYMENT.md).
