import { createHash, randomBytes, randomUUID } from 'node:crypto';
export type Json = Record<string, any>;
export class ApiError extends Error {
  constructor(public code: string, message: string, public status = 400) { super(message); }
}
export const fail = (code: string, message: string, status = 400): never => { throw new ApiError(code, message, status); };
export const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));
export const object = (value: unknown): value is Json => value !== null && typeof value === 'object' && !Array.isArray(value);
export const newId = (prefix: string): string => `${prefix}-${randomUUID()}`;
export const newToken = (): string => randomBytes(32).toString('hex');
export const stable = (value: any): string => JSON.stringify(value, (_key, v) => object(v) ? Object.fromEntries(Object.keys(v).sort().map(k => [k, v[k]])) : v);
export const digest = (value: string): string => createHash('sha256').update(value).digest('hex');
export function text(value: any, label: string, max = 200, empty = false): string {
  if (typeof value !== 'string' || value.length > max || (!empty && !value.trim()) || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\uD800-\uDFFF]/u.test(value)) return fail('22023', `Invalid ${label}.`);
  return value.trim();
}
export function identifier(value: any, label = 'identifier'): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) return fail('22023', `Invalid ${label}.`);
  return value;
}
export function uidIdentifier(value: any): boolean { return typeof value === 'string' && /^[A-Za-z0-9:_-]{1,128}$/.test(value); }
export function requestId(value: any): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(value)) return fail('22023', 'Provide a unique request ID.');
  return value;
}
export function validateItems(input: any, allowEmpty = false): Json[] {
  if (!Array.isArray(input) || input.length > 100 || (!allowEmpty && !input.length)) return fail('22023', 'Provide one to one hundred plan items.');
  const seen = new Set();
  return input.map(value => {
    if (!object(value)) return fail('22023', 'Invalid plan item.');
    const id = identifier(value.id, 'item ID');
    if (seen.has(id)) return fail('22023', 'Item IDs must be unique.'); seen.add(id);
    const title = text(value.title, 'item title', 500);
    const details = text(value.details ?? '', 'item details', 10000, true);
    const ownerId = value.ownerId ?? 'you';
    if (!['you', 'client'].includes(ownerId)) return fail('22023', 'Invalid item owner.');
    const currency = value.currency ?? 'USD';
    if (typeof currency !== 'string' || !/^[A-Z]{3}$/.test(currency)) return fail('22023', 'Use a three-letter currency code.');
    const amountMinor = value.amountMinor ?? null;
    if (amountMinor !== null && (!Number.isSafeInteger(amountMinor) || amountMinor < 0)) return fail('22023', 'Amounts must be nonnegative integer minor units.');
    let dueDate = value.dueDate ?? null;
    if (dueDate !== null) {
      if (typeof dueDate !== 'string' || !/^\d{4}-\d{2}-\d{2}(T00:00:00(\.0{1,6})?(Z|\+00:00)?)?$/.test(dueDate)) return fail('22023', 'Deadlines must be date-only values.');
      const day = dueDate.slice(0, 10);
      if (!Number.isFinite(Date.parse(`${day}T00:00:00Z`)) || new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) !== day) return fail('22023', 'Invalid deadline.');
      dueDate = `${day}T00:00:00.000`;
    }
    return { id, title, details, ownerId, dueDate, amountMinor, currency };
  });
}
export function validateEvidence(input: any, now: string): Json[] {
  if (!Array.isArray(input) || !input.length || input.length > 20) return fail('22023', 'Add one to twenty sources.');
  const seen = new Set();
  return input.map(value => {
    if (!object(value)) return fail('22023', 'Invalid source.');
    const id = identifier(value.id, 'source ID');
    if (seen.has(id)) return fail('22023', 'Source IDs must be unique.'); seen.add(id);
    text(value.text, 'source text', 30000);
    const language = text(value.language, 'source language', 80);
    if (!['originalText', 'personalRecollection'].includes(value.kind) || value.attachmentPath != null) return fail('22023', 'Invalid source. Recording paths must stay on your device.');
    return { id, text: value.text, language, kind: value.kind, createdAt: now, attachmentPath: null };
  });
}
export function event(message: string, actorId: string, createdAt: string, revisionId: string | null = null): Json { return { id: newId('event'), message, actorId, createdAt, revisionId }; }
export function revisionHash(r: Json): string {
  const { status: _status, acceptedBy: _accepted, correctionNote: _note, ...payload } = r;
  return digest(stable(payload));
}
export function changedIds(base: Json, revision: Json): string[] {
  const old = new Map(base.items.map((i: Json) => [i.id, stable(i)]));
  const next = new Map(revision.items.map((i: Json) => [i.id, stable(i)]));
  return [...new Set([...old.keys(), ...next.keys()])].filter(id => old.get(id) !== next.get(id)).sort() as string[];
}
export function allRevisions(project: Json): Json[] {
  const map = new Map<string, Json>();
  for (const r of [...project.archivedRevisions, ...project.proposals, project.currentRevision]) map.set(r.id, r);
  return [...map.values()].sort((a, b) => a.number - b.number);
}
export function createProject(title: any, clientName: any, category: any, now: string): Json {
  title = text(title, 'project title'); clientName = text(clientName, 'client name'); category = text(category, 'category', 80);
  const revision = { id: newId('revision'), number: 1, baseRevisionId: null, createdAt: now, authorId: 'you', items: [], requiredParticipantIds: ['you'], acceptedBy: ['you'], evidence: [], status: 'confirmed', correctionNote: null };
  return { id: newId('project'), title, clientName, category, participants: [{ id: 'you', name: 'You', role: 'Creator' }, { id: 'client', name: clientName, role: 'Client' }], currentRevision: revision, proposals: [], archivedRevisions: [], history: [event('Created a private project plan. No client confirmation recorded.', 'you', now, revision.id)], itemStatuses: {}, isDemo: false };
}
export function mutate(project: Json, action: string, payload: Json, now: string): Json {
  project = clone(project);
  if (!object(payload) || Buffer.byteLength(stable(payload)) > 800000) return fail('22023', 'Invalid action payload.');
  if ((payload.actorId ?? payload.authorId ?? 'you') !== 'you') return fail('42501', 'An owner cannot record a client response. Share a review link.', 403);
  const current = project.currentRevision;
  const nextNumber = () => Math.max(...allRevisions(project).map(r => r.number)) + 1;
  if (action === 'add_item') {
    if (stable(current.requiredParticipantIds) !== '["you"]') return fail('22023', 'This plan is shared. Propose a change.');
    const [item] = validateItems([payload.item]);
    if (current.items.length >= 100 || current.items.some((old: Json) => old.id === item.id)) return fail('22023', 'That item already exists or the plan is full.');
    const next = { id: newId('revision'), number: nextNumber(), baseRevisionId: current.id, createdAt: now, authorId: 'you', items: [...current.items, item], requiredParticipantIds: ['you'], acceptedBy: ['you'], evidence: [], status: 'confirmed', correctionNote: null };
    project.currentRevision = next; project.archivedRevisions.push(current);
    project.history.push(event('Added an item to your private plan. No client confirmation recorded.', 'you', now, next.id));
  } else if (action === 'propose_change') {
    const items = validateItems(payload.items); const evidence = validateEvidence(payload.evidence, now);
    if (stable(items) === stable(current.items)) return fail('22023', 'The proposal must change at least one item.');
    if (payload.requiredParticipantIds && stable(payload.requiredParticipantIds) !== '["you","client"]') return fail('22023', 'Both project participants must review shared changes.');
    const next = { id: newId('revision'), number: nextNumber(), baseRevisionId: current.id, createdAt: now, authorId: 'you', items, requiredParticipantIds: ['you', 'client'], acceptedBy: ['you'], evidence, status: 'proposed', correctionNote: null };
    project.proposals.push(next); project.history.push(event(`Proposed version ${next.number}. The current plan stays unchanged.`, 'you', now, next.id));
  } else if (['confirm', 'correction'].includes(action)) {
    const r = project.proposals.find((r: Json) => r.id === payload.revisionId);
    if (!r) return fail('P0002', 'Proposal not found.', 404);
    if (r.status !== 'proposed' || r.baseRevisionId !== current.id) return fail('40001', 'This proposal is closed or stale. Create a new proposal.', 409);
    if (action === 'correction') {
      r.correctionNote = text(payload.note, 'correction', 2000); r.status = 'correctionRequested'; r.acceptedBy = [];
      project.history.push(event(`Correction requested: ${r.correctionNote}`, 'you', now, r.id));
    }
  } else if (action === 'set_status') {
    const item = current.items.find((i: Json) => i.id === payload.itemId);
    if (!item) return fail('22023', 'That item is not in the current plan.');
    const status = payload.status; const prior = project.itemStatuses[item.id] ?? 'open';
    if (!['open', 'inProgress', 'delivered', 'accepted'].includes(status)) return fail('22023', 'Invalid progress status.');
    if (status === 'accepted' && (prior !== 'delivered' || item.ownerId === 'you')) return fail('42501', 'Only the recipient can accept after delivery.', 403);
    if (status !== 'accepted' && item.ownerId !== 'you') return fail('42501', 'Only the item owner can record progress.', 403);
    project.itemStatuses[item.id] = status;
    project.history.push(event(`Item progress: ${status}. This does not record payment.`, 'you', now));
  } else return fail('22023', 'Unsupported project action.');
  return project;
}
export function publish(project: Json, revision: Json): void {
  const current = project.currentRevision;
  project.itemStatuses = Object.fromEntries(revision.items.filter((i: Json) => current.items.some((old: Json) => old.id === i.id && stable(old) === stable(i))).filter((i: Json) => project.itemStatuses[i.id] !== undefined).map((i: Json) => [i.id, project.itemStatuses[i.id]]));
  revision.status = 'confirmed'; project.archivedRevisions.push(current); project.currentRevision = revision;
}
