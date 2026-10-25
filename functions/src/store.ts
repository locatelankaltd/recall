import type { Firestore, Transaction, DocumentSnapshot } from 'firebase-admin/firestore';
import { ApiError, allRevisions, changedIds, clone, createProject, digest, event, fail, identifier, Json, mutate, newId, newToken, object, publish, requestId, revisionHash, stable, text, uidIdentifier } from './domain.js';
const RESPONSE_MAX = 5 * 1024 * 1024;
export const WORKSPACE_MAX = 6 * 1024 * 1024;
const REVIEW_HEADROOM = 32768;
const CHUNK = 450000;
const ownerPath = (uid: string) => `recallOwners/${uid}`;
const projectPath = (id: string) => `recallProjects/${identifier(id, 'project ID')}`;
export class RecallStore {
  constructor(public db: Firestore, public clock: () => number = Date.now, private options: { allowSandbox?: () => boolean } = {}) {}
  private now(): string { return new Date(this.clock()).toISOString(); }
  private owner(uid: string) {
    if (!uidIdentifier(uid)) return fail('28000', 'Sign in to access your workspace.', 401);
    return this.db.doc(ownerPath(uid));
  }
  private deletionFence(uid: string) { return this.db.collection('recallDeletedOwners').doc(digest(uid)); }
  private async ownerState(tx: Transaction, uid: string): Promise<Json> {
    const [fence, doc] = await tx.getAll(this.deletionFence(uid), this.owner(uid));
    if (fence.exists || doc.data()?.deleting) return fail('42501', 'Account deletion is in progress.', 403);
    return doc.data() ?? { projectCount: 0 };
  }
  private plan(raw: Json | undefined): Json {
    const fresh = raw && Date.parse(raw.verifiedAt) > this.clock() - 86400000;
    const active = !!(raw?.active && fresh && (raw.environment === 'production' || (raw.environment === 'sandbox' && this.options.allowSandbox?.() === true)) && (raw.expiresAt === null || Date.parse(raw.expiresAt) > this.clock()));
    return { entitlement: 'pro', active, expiresAt: raw?.expiresAt ?? null, verifiedAt: raw?.verifiedAt ?? null, environment: raw?.environment ?? 'unknown', status: !raw ? 'unverified' : !fresh ? 'stale' : active ? 'active' : 'inactive', projectLimit: active ? 100 : 3, analysisDailyLimit: active ? 20 : 5 };
  }
  private async limits(tx: Transaction, uid: string): Promise<Json> { return this.plan((await tx.get(this.owner(uid).collection('entitlements').doc('pro'))).data()); }
  private workspaceCharge(project: Json, version: number): number {
    // Publishing duplicates the selected proposal in currentRevision. Reserve that
    // copy and enough space for a bounded correction note/history before sharing.
    const reviewReserve = project.proposals.filter((r: Json) => r.status === 'proposed').reduce((sum: number, r: Json) => sum + Buffer.byteLength(stable(r)) + REVIEW_HEADROOM, 0);
    return Buffer.byteLength(stable({ project, version })) + reviewReserve + 128;
  }
  private budget(tx: Transaction, uid: string, owner: Json, prior: Json | undefined, project: Json, version: number): number {
    const charge = this.workspaceCharge(project, version);
    if (charge > RESPONSE_MAX) return fail('54000', 'This project reached its size limit. Export or delete it before adding more content.', 429);
    const aggregate = (owner.workspaceBudgetBytes ?? 0) - (prior?.budgetBytes ?? 0) + charge;
    if (!Number.isSafeInteger(aggregate) || aggregate < 0 || aggregate > WORKSPACE_MAX) return fail('54000', 'This workspace reached its size limit. Export or delete a project before adding more content.', 429);
    tx.set(this.owner(uid), { workspaceBudgetBytes: aggregate }, { merge: true });
    return charge;
  }
  private async load(tx: Transaction, id: string, uid?: string): Promise<{ project: Json; record: Json }> {
    const ref = this.db.doc(projectPath(id));
    const snapshot = await tx.get(ref); const record = snapshot.data();
    if (!record || record.deleted || (uid && record.ownerId !== uid)) return fail('P0002', 'Project not found.', 404);
    const revisions = await tx.get(ref.collection('revisions'));
    const events = await tx.get(ref.collection('events'));
    const all: Json[] = revisions.docs.map((doc): Json => {
      const data = doc.data();
      if (!object(data.model) || data.contentHash !== revisionHash(data.model) || !Array.isArray(data.model.acceptedBy) || data.model.acceptedBy.length !== new Set(data.model.acceptedBy).size || data.model.acceptedBy.some((actor: string) => !data.model.requiredParticipantIds.includes(actor)) || (data.model.status === 'confirmed' && !data.model.requiredParticipantIds.every((actor: string) => data.model.acceptedBy.includes(actor)))) return fail('40001', 'A stored revision could not be verified. Contact support.', 409);
      return { ...data.model, isProposal: data.isProposal };
    }).sort((a, b) => a.number - b.number);
    const clean = (r: Json): Json => { const { isProposal: _proposal, ...model } = r; return model; };
    const current = all.find(r => r.id === record.currentRevisionId);
    if (!current || current.status !== 'confirmed') return fail('40001', 'The stored current plan could not be verified.', 409);
    const project = { id, title: record.title, clientName: record.clientName, category: record.category, participants: [{ id: 'you', name: 'You', role: 'Creator' }, { id: 'client', name: record.clientName, role: 'Client' }], currentRevision: clean(current), proposals: all.filter(r => r.isProposal).map(clean), archivedRevisions: all.filter(r => r.status === 'confirmed' && r.id !== current.id).map(clean), history: events.docs.sort((a, b) => a.data().ordinal - b.data().ordinal).map(doc => doc.data().model), itemStatuses: record.itemStatuses ?? {}, isDemo: false };
    return { project, record };
  }
  private persist(tx: Transaction, uid: string, project: Json, version: number, owner: Json, before?: Json, priorRecord?: Json): void {
    const budgetBytes = this.budget(tx, uid, owner, priorRecord, project, version);
    const ref = this.db.doc(projectPath(project.id));
    const old = new Map(before ? allRevisions(before).map(r => [r.id, r]) : []);
    const proposals = new Set(project.proposals.map((r: Json) => r.id));
    for (const r of allRevisions(project)) {
      if (Buffer.byteLength(stable(r)) > 850000) return fail('54000', 'This revision reached the service size limit.', 429);
      const prior = old.get(r.id);
      if (prior && revisionHash(prior) !== revisionHash(r)) return fail('22023', 'Revision content is immutable. Create a new proposal.');
      if (!prior || stable(prior) !== stable(r)) tx.set(ref.collection('revisions').doc(r.id), { model: r, contentHash: revisionHash(r), isProposal: proposals.has(r.id) });
    }
    const priorEvents = new Set(before?.history.map((e: Json) => e.id) ?? []);
    project.history.forEach((e: Json, ordinal: number) => { if (!priorEvents.has(e.id)) tx.create(ref.collection('events').doc(e.id), { model: e, ordinal }); });
    tx.set(ref, { ownerId: uid, title: project.title, clientName: project.clientName, category: project.category, currentRevisionId: project.currentRevision.id, itemStatuses: project.itemStatuses, version, deleted: false, budgetBytes, updatedAt: this.now() }, { merge: true });
  }
  private journalRef(uid: string, id: string) { return this.owner(uid).collection('requests').doc(requestId(id)); }
  private tombstone(id: string, version: number): Json { return { project: null, version, deleted: true, projectId: id }; }
  private async cached(tx: Transaction, uid: string, id: string, fingerprint: string): Promise<Json | null> {
    const snapshot = await tx.get(this.journalRef(uid, id)); const data = snapshot.data();
    if (!data) return null;
    if (data.fingerprint !== fingerprint) return fail('22023', 'Request ID already used for another action.');
    const project = await tx.get(this.db.doc(projectPath(data.projectId)));
    if (!project.exists || project.data()?.deleted) return this.tombstone(data.projectId, project.data()?.version ?? data.version);
    if (data.response) return clone(data.response);
    const refs = Array.from({ length: data.chunkCount }, (_, index) => snapshot.ref.collection('requestChunks').doc(String(index)));
    const chunks = await tx.getAll(...refs);
    const raw = Buffer.concat(chunks.map(doc => Buffer.from(doc.data()?.data ?? '', 'base64'))).toString('utf8');
    if (digest(raw) !== data.responseHash) return fail('40001', 'The saved response could not be verified.', 409);
    return JSON.parse(raw);
  }
  private journal(tx: Transaction, uid: string, id: string, fingerprint: string, response: Json, projectId: string): void {
    const raw = stable(response); const bytes = Buffer.from(raw);
    if (bytes.length > RESPONSE_MAX) return fail('54000', 'This project reached the service response limit. Export and contact support.', 429);
    const ref = this.journalRef(uid, id);
    if (bytes.length < CHUNK) tx.create(ref, { fingerprint, response, projectId, version: response.version, chunkCount: 0 });
    else {
      const count = Math.ceil(bytes.length / CHUNK);
      tx.create(ref, { fingerprint, responseHash: digest(raw), projectId, version: response.version, chunkCount: count });
      for (let index = 0; index < count; index++) tx.create(ref.collection('requestChunks').doc(String(index)), { data: bytes.subarray(index * CHUNK, (index + 1) * CHUNK).toString('base64') });
    }
  }
  async listProjects(uid: string): Promise<Json[]> {
    return this.db.runTransaction(async tx => {
      const owner = await this.ownerState(tx, uid);
      if ((owner.workspaceBudgetBytes ?? 0) > WORKSPACE_MAX) return fail('54000', 'The workspace reached the service response limit.', 429);
      const docs = await tx.get(this.db.collection('recallProjects').where('ownerId', '==', uid).where('deleted', '==', false).limit(101));
      const records = docs.docs.filter(doc => !doc.data().deleted).sort((a, b) => b.data().updatedAt.localeCompare(a.data().updatedAt));
      if (records.length > 100 || records.reduce((sum, doc) => sum + (doc.data().budgetBytes ?? WORKSPACE_MAX + 1), 0) > WORKSPACE_MAX) return fail('54000', 'The workspace reached the service response limit.', 429);
      const result = []; let responseBytes = 16;
      for (const record of records) {
        const loaded = await this.load(tx, record.id, uid); const envelope = { project: loaded.project, version: loaded.record.version };
        responseBytes += Buffer.byteLength(stable(envelope)) + 1;
        if (responseBytes > WORKSPACE_MAX) return fail('54000', 'The workspace reached the service response limit.', 429);
        result.push(envelope);
      }
      return result;
    });
  }
  async create(uid: string, params: Json): Promise<Json> {
    const rid = requestId(params.p_request_id); const fingerprint = digest(stable(['create', params.p_title, params.p_client_name, params.p_category]));
    const next = createProject(params.p_title, params.p_client_name, params.p_category, this.now());
    return this.db.runTransaction(async tx => {
      const owner = await this.ownerState(tx, uid); const cached = await this.cached(tx, uid, rid, fingerprint); if (cached) return cached;
      const plan = await this.limits(tx, uid);
      if ((owner.projectCount ?? 0) >= plan.projectLimit) return fail('54000', 'Your project limit has been reached. Free supports 3 projects; verified Pro supports 100.', 429);
      const response = { project: next, version: 1 };
      this.persist(tx, uid, next, 1, owner); this.journal(tx, uid, rid, fingerprint, response, next.id);
      tx.set(this.owner(uid), { projectCount: (owner.projectCount ?? 0) + 1 }, { merge: true });
      return response;
    });
  }
  async mutate(uid: string, params: Json): Promise<Json> {
    const id = identifier(params.p_project_id); const rid = requestId(params.p_request_id);
    const payload = params.p_payload ?? {}; const action = params.p_action;
    const fingerprint = digest(stable(['mutate', id, params.p_expected_version, action, payload]));
    const result = await this.db.runTransaction(async tx => {
      const owner = await this.ownerState(tx, uid); const cached = await this.cached(tx, uid, rid, fingerprint); if (cached) return cached;
      const { project, record } = await this.load(tx, id, uid);
      if (!Number.isSafeInteger(params.p_expected_version) || params.p_expected_version !== record.version) return fail('40001', 'The project changed. Refresh and review the latest version.', 409);
      if (!object(payload) || Buffer.byteLength(stable(payload)) > 800000) return fail('22023', 'Invalid action payload.');
      if ((payload.actorId ?? payload.authorId ?? 'you') !== 'you') return fail('42501', 'An owner cannot record a client response.', 403);
      const version = record.version + 1;
      if (action === 'delete') {
        const response = this.tombstone(id, version);
        tx.update(this.db.doc(projectPath(id)), { deleted: true, version });
        tx.set(this.owner(uid), { projectCount: Math.max(0, (owner.projectCount ?? 1) - 1), workspaceBudgetBytes: Math.max(0, (owner.workspaceBudgetBytes ?? 0) - (record.budgetBytes ?? 0)) }, { merge: true });
        this.journal(tx, uid, rid, fingerprint, response, id); return response;
      }
      const next = mutate(project, action, payload, this.now());
      const response = { project: next, version };
      if (action === 'correction') tx.delete(this.db.doc(projectPath(id)).collection('coverage').doc(payload.revisionId));
      this.persist(tx, uid, next, version, owner, project, record); this.journal(tx, uid, rid, fingerprint, response, id);
      return response;
    });
    if (action === 'delete') await this.purgeProject(uid, id, result.version);
    return result;
  }
  private async purgeProject(uid: string, id: string, version: number): Promise<void> {
    const requests = await this.owner(uid).collection('requests').where('projectId', '==', id).get();
    for (const doc of requests.docs) {
      const chunks = await doc.ref.collection('requestChunks').get();
      for (const chunk of chunks.docs) await chunk.ref.delete();
      await doc.ref.set({ fingerprint: doc.data().fingerprint, projectId: id, version, chunkCount: 0, response: this.tombstone(id, version) });
    }
    const links = await this.db.collection('recallReviewLinks').where('projectId', '==', id).get();
    for (const link of links.docs) await link.ref.delete();
    await this.db.recursiveDelete(this.db.doc(projectPath(id)));
  }
  private async link(tx: Transaction, token: any, active = true): Promise<{ snapshot: DocumentSnapshot; data: Json }> {
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) return fail('P0002', 'Review link unavailable.', 404);
    const snapshot = await tx.get(this.db.collection('recallReviewLinks').doc(digest(token))); const data = snapshot.data();
    if (!data) return fail('P0002', 'Review link unavailable.', 404);
    await this.ownerState(tx, data.ownerId);
    if (active && (data.revokedAt || Date.parse(data.expires) <= this.clock())) return fail('P0002', 'Review link unavailable or expired.', 404);
    return { snapshot, data };
  }
  async createLink(uid: string, params: Json): Promise<Json> {
    const token = newToken(); const id = newId('link');
    return this.db.runTransaction(async tx => {
      await this.ownerState(tx, uid); const { project } = await this.load(tx, params.p_project_id, uid);
      const revision = project.proposals.find((r: Json) => r.id === params.p_revision_id);
      if (!revision) return fail('P0002', 'Proposal not found.', 404);
      if (revision.status !== 'proposed' || revision.baseRevisionId !== project.currentRevision.id) return fail('40001', 'This proposal is closed or stale.', 409);
      if (params.p_participant_id !== 'client') return fail('22023', 'Choose the client participant.');
      const ttl = params.p_ttl_seconds ?? 86400;
      if (!Number.isInteger(ttl) || ttl < 60 || ttl > 604800) return fail('22023', 'Links expire between one minute and seven days.');
      const changed = changedIds(project.currentRevision, revision); const selected = params.p_item_ids ?? changed;
      if (!Array.isArray(selected) || !selected.length || selected.length !== new Set(selected).size || selected.some(i => !changed.includes(i))) return fail('22023', 'Select unique changed item IDs.');
      const expires = new Date(this.clock() + ttl * 1000).toISOString();
      tx.create(this.db.collection('recallReviewLinks').doc(digest(token)), { id, ownerId: uid, projectId: project.id, revisionId: revision.id, participantId: 'client', itemIds: selected, expires, revokedAt: null, createdAt: this.now() });
      return { id, token, expires, revisionId: revision.id, participantId: 'client', itemIds: selected, identity: 'link-holder response; identity not verified' };
    });
  }
  async listLinks(uid: string, params: Json): Promise<Json[]> {
    return this.db.runTransaction(async tx => {
      await this.ownerState(tx, uid); await this.load(tx, params.p_project_id, uid);
      const links = await tx.get(this.db.collection('recallReviewLinks').where('projectId', '==', params.p_project_id));
      return links.docs.map(doc => { const l = doc.data(); return { id: l.id, revisionId: l.revisionId, participantId: l.participantId, itemIds: l.itemIds, expires: l.expires, revoked: !!l.revokedAt, responded: !!l.response }; });
    });
  }
  async revokeLink(uid: string, params: Json): Promise<Json> {
    return this.db.runTransaction(async tx => {
      await this.ownerState(tx, uid);
      const query = await tx.get(this.db.collection('recallReviewLinks').where('id', '==', params.p_link_id).limit(1)); const doc = query.docs[0];
      if (!doc || doc.data().ownerId !== uid) return fail('P0002', 'Review link not found.', 404);
      await this.load(tx, doc.data().projectId, uid); tx.update(doc.ref, { revokedAt: doc.data().revokedAt ?? this.now() });
      return { id: doc.data().id, revoked: true };
    });
  }
  async review(token: any): Promise<Json> {
    return this.db.runTransaction(async tx => {
      const { data: l } = await this.link(tx, token); const { project } = await this.load(tx, l.projectId, l.ownerId);
      const revision = project.proposals.find((r: Json) => r.id === l.revisionId);
      if (!revision) return fail('P0002', 'Proposal unavailable.', 404);
      const base = allRevisions(project).find(r => r.id === revision.baseRevisionId);
      if (!base) return fail('P0002', 'Base plan unavailable.', 404);
      const status = revision.status === 'proposed' && revision.baseRevisionId !== project.currentRevision.id ? 'stale' : revision.status;
      const full = changedIds(base, revision).every(id => l.itemIds.includes(id));
      return { projectTitle: project.title, participantName: project.clientName, revisionId: revision.id, version: revision.number, baseRevisionId: revision.baseRevisionId, currentRevisionId: project.currentRevision.id, status, changes: l.itemIds.map((id: string) => ({ itemId: id, previous: base.items.find((i: Json) => i.id === id) ?? null, proposed: revision.items.find((i: Json) => i.id === id) ?? null })), evidence: full ? revision.evidence : [], evidenceOmitted: !full, canRespond: status === 'proposed' && !l.response, response: l.response ? { receiptId: l.response.receiptId, action: l.response.action, note: l.responseNote, identity: l.response.identity } : null, identity: 'link-holder response; identity not verified' };
    });
  }
  async respond(params: Json): Promise<Json> {
    const rid = requestId(params.p_request_id); const action = params.p_action; const note = text(params.p_note ?? '', 'response note', 2000, action !== 'correction');
    if (!['confirm', 'correction', 'decline'].includes(action)) return fail('22023', 'Choose confirm, correction or decline.');
    return this.db.runTransaction(async tx => {
      const { snapshot: linkDoc, data: l } = await this.link(tx, params.p_token, false);
      const owner = await this.ownerState(tx, l.ownerId);
      const { project, record } = await this.load(tx, l.projectId, l.ownerId);
      const fingerprint = digest(stable([l.revisionId, action, note]));
      if (l.response) {
        if (l.responseRequestId !== rid || l.responseFingerprint !== fingerprint) return fail('40001', 'A response is already recorded. Request a new proposal to change it.', 409);
        return clone(l.response);
      }
      if (l.revokedAt || Date.parse(l.expires) <= this.clock()) return fail('P0002', 'Review link unavailable or expired.', 404);
      const next = clone(project); const revision = next.proposals.find((r: Json) => r.id === l.revisionId);
      if (!revision || revision.status !== 'proposed' || revision.baseRevisionId !== next.currentRevision.id) return fail('40001', 'This proposal is closed or stale.', 409);
      const changed = changedIds(next.currentRevision, revision);
      const coverageRef = this.db.doc(projectPath(l.projectId)).collection('coverage').doc(revision.id);
      const previousCoverage = (await tx.get(coverageRef)).data()?.client ?? [];
      if (action === 'confirm') {
        const client = [...new Set([...previousCoverage, ...l.itemIds])];
        if (changed.every(id => client.includes(id))) { revision.acceptedBy = ['you', 'client']; publish(next, revision); }
        tx.set(coverageRef, { client });
      } else {
        revision.status = action === 'correction' ? 'correctionRequested' : 'rejected'; revision.acceptedBy = []; revision.correctionNote = note || null;
        tx.delete(coverageRef);
      }
      next.history.push(event(`A review link holder recorded ${action} for version ${revision.number}. Identity not verified.`, 'client', this.now(), revision.id));
      const response = { receiptId: newId('receipt'), revisionId: revision.id, version: revision.number, action, status: revision.status, identity: 'link-holder response; identity not verified' };
      this.persist(tx, l.ownerId, next, record.version + 1, owner, project, record);
      tx.update(linkDoc.ref, { response, responseNote: note, responseRequestId: rid, responseFingerprint: fingerprint });
      return response;
    });
  }
  async entitlement(uid: string): Promise<Json> { return this.db.runTransaction(async tx => { await this.ownerState(tx, uid); return this.limits(tx, uid); }); }
  async reserveAnalysis(uid: string, adminCap = 20): Promise<boolean> {
    if (!Number.isInteger(adminCap) || adminCap < 1 || adminCap > 100) return fail('22023', 'Invalid analysis allowance.');
    const day = this.now().slice(0, 10);
    return this.db.runTransaction(async tx => {
      await this.ownerState(tx, uid); const plan = await this.limits(tx, uid);
      const userRef = this.owner(uid).collection('analysisUsage').doc(day); const serviceRef = this.db.collection('recallServiceUsage').doc(day);
      const [u, global] = await tx.getAll(userRef, serviceRef); const userCount = u.data()?.count ?? 0; const serviceCount = global.data()?.count ?? 0;
      if (userCount >= Math.min(plan.analysisDailyLimit, adminCap) || serviceCount >= 100) return false;
      tx.set(userRef, { count: userCount + 1 }); tx.set(serviceRef, { count: serviceCount + 1 }); return true;
    });
  }
  async eventSeen(id: string): Promise<boolean> { return (await this.db.collection('recallBillingEvents').doc(digest(id)).get()).exists; }
  async applyBilling(updates: Json[], eventId: string | null): Promise<Json> {
    if (!Array.isArray(updates) || !updates.length || updates.length > 20) return fail('22023', 'Invalid billing update.');
    return this.db.runTransaction(async tx => {
      const eventRef = eventId ? this.db.collection('recallBillingEvents').doc(digest(text(eventId, 'billing event', 200))) : null;
      if (eventRef && (await tx.get(eventRef)).exists) return { duplicate: true, applied: 0 };
      const reads = [];
      for (const update of [...updates].sort((a, b) => a.ownerId.localeCompare(b.ownerId))) {
        if (!uidIdentifier(update.ownerId) || typeof update.active !== 'boolean' || !['production', 'sandbox', 'unknown'].includes(update.environment) || !Number.isFinite(Date.parse(update.observedAt)) || Math.abs(Date.parse(update.observedAt) - this.clock()) > 300000) return fail('22023', 'Invalid verified billing state.');
        const owner = await tx.get(this.owner(update.ownerId)); const fence = await tx.get(this.deletionFence(update.ownerId)); const ref = this.owner(update.ownerId).collection('entitlements').doc('pro'); const existing = await tx.get(ref);
        reads.push({ update, owner, fence, ref, existing });
      }
      let applied = 0;
      for (const { update, owner, fence, ref, existing } of reads) {
        if (fence.exists || owner.data()?.deleting || (existing.exists && Date.parse(existing.data()?.observedAt) > Date.parse(update.observedAt))) continue;
        tx.set(ref, { active: update.active, expiresAt: update.expiresAt ?? null, environment: update.environment, observedAt: update.observedAt, verifiedAt: this.now() }); applied++;
      }
      if (eventRef) tx.create(eventRef, { processedAt: this.now() }); return { duplicate: false, applied };
    });
  }
  async deleteAccount(uid: string, deleteAuth: () => Promise<void>): Promise<void> {
    await this.db.runTransaction(async tx => {
      const ref = this.owner(uid); const fence = this.deletionFence(uid);
      const existing = await tx.get(fence); await tx.get(ref);
      if (!existing.exists) tx.create(fence, { deletedAt: this.now() });
      tx.set(ref, { deleting: true }, { merge: true });
    });
    const projects = await this.db.collection('recallProjects').where('ownerId', '==', uid).get();
    for (const project of projects.docs) await this.purgeProject(uid, project.id, project.data().version + 1);
    const links = await this.db.collection('recallReviewLinks').where('ownerId', '==', uid).get();
    for (const link of links.docs) await link.ref.delete();
    // Retain the deletion barrier until Auth deletion succeeds; retries can resume.
    for (const subcollection of await this.owner(uid).listCollections()) await this.db.recursiveDelete(subcollection);
    await deleteAuth(); await this.owner(uid).delete();
  }
  async rpc(name: string, params: Json, uid: string | null): Promise<any> {
    if (!object(params)) return fail('22023', 'Invalid RPC parameters.');
    if (name === 'recall_review_link') return this.review(params.p_token);
    if (name === 'recall_respond_review') return this.respond(params);
    if (!uid) return fail('28000', 'Sign in to access your workspace.', 401);
    switch (name) {
      case 'recall_list_projects': return this.listProjects(uid);
      case 'recall_create_project': return this.create(uid, params);
      case 'recall_mutate_project': return this.mutate(uid, params);
      case 'recall_create_review_link': return this.createLink(uid, params);
      case 'recall_list_review_links': return this.listLinks(uid, params);
      case 'recall_revoke_review_link': return this.revokeLink(uid, params);
      case 'recall_entitlement': return this.entitlement(uid);
      default: return fail('42501', 'This operation is unavailable to clients.', 403);
    }
  }
}
