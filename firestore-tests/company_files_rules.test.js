// Company Files V1 Firestore and Storage boundary regression.
const fs = require('node:fs');
const path = require('node:path');
const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');
const { deleteObject, getBytes, listAll, ref, uploadBytes } = require('firebase/storage');

const PROJECT = 'demo-yovoice-company-files-rules';
const OWNER = 'company-owner';
const MEMBER = 'company-member';
const OUTSIDER = 'company-outsider';
const SERVER = 'company-server';
const CHANNEL = 'files';
const FILE_ID = 'cf_0123456789abcdef0123456789abcdef01234567';
const FILE_PATH = 'server_company_files/' + SERVER + '/' + CHANNEL + '/' + OWNER + '/' + FILE_ID + '.pdf';
const FILE_BYTES = Buffer.from('%PDF-1.7\nbody\n%%EOF');
let env;

function endpoint(value, fallback) {
  const parts = (value || ('127.0.0.1:' + fallback)).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function server() {
  return {
    serverSchemaVersion: 1,
    serverType: 'company',
    templateVersion: 1,
    serverActivationState: 'active',
    revision: 1,
    status: 'active',
    // V1 roots retain the legacy wire type outside Family; `serverType`
    // carries the exact product template.
    type: 'community',
    ownerId: OWNER,
    privacy: 'inviteOnly',
    name: 'Company',
    description: '',
    memberCount: 2,
    onlineCount: 0,
    defaultLanguage: 'English',
  };
}

function member(uid, role) {
  return {
    userId: uid,
    role,
    displayName: uid,
    photoUrl: null,
    authorizationRevision: 1,
    joinedAt: new Date(0),
    isOnline: false,
  };
}

function channel() {
  return {
    serverSchemaVersion: 1,
    serverId: SERVER,
    kind: 'files',
    type: 'files',
    revision: 1,
    aclRevision: 1,
    status: 'active',
    name: 'Files',
    position: 0,
    roomId: null,
    activeSessionId: null,
    experience: null,
    mediaMode: null,
    isPrivate: false,
    accessMode: 'members',
    accessPolicy: { accessMode: 'members', roleIds: [], userIds: [] },
    liveness: { schemaVersion: 1, isLive: false, startedAt: null },
  };
}

function file() {
  return {
    schemaVersion: 1,
    fileKind: 'companyFile',
    serverId: SERVER,
    clubId: SERVER,
    channelId: CHANNEL,
    fileId: FILE_ID,
    ownerId: OWNER,
    ownerDisplayName: OWNER,
    ownerPhotoUrl: null,
    displayName: 'Quarterly plan.pdf',
    status: 'published',
    file: {
      storagePath: FILE_PATH,
      generation: '1',
      contentType: 'application/pdf',
      size: FILE_BYTES.length,
    },
    revision: 1,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}

function reservation() {
  return {
    schemaVersion: 1,
    kind: 'serverCompanyFile',
    serverId: SERVER,
    channelId: CHANNEL,
    fileId: FILE_ID,
    ownerId: OWNER,
    requestId: 'company-file-rules-reservation',
    displayName: 'Quarterly plan.pdf',
    storagePath: FILE_PATH,
    contentType: 'application/pdf',
    size: FILE_BYTES.length,
    status: 'uploading',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 60 * 60_000),
  };
}

function metadata(overrides = {}) {
  return {
    yovoiceServerId: SERVER,
    yovoiceChannelId: CHANNEL,
    yovoiceOwnerUid: OWNER,
    yovoiceFileId: FILE_ID,
    yovoiceAssetKind: 'companyFile',
    ...overrides,
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      ...endpoint(process.env.FIRESTORE_EMULATOR_HOST, 8080),
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
    },
    storage: {
      ...endpoint(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 9199),
      rules: fs.readFileSync(path.join(__dirname, '../storage.rules'), 'utf8'),
    },
  });
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const entries = {
      ['users/' + OWNER]: { displayName: OWNER, status: 'active', disabled: false },
      ['users/' + MEMBER]: { displayName: MEMBER, status: 'active', disabled: false },
      ['users/' + OUTSIDER]: { displayName: OUTSIDER, status: 'active', disabled: false },
      ['clubs/' + SERVER]: server(),
      ['clubs/' + SERVER + '/members/' + OWNER]: member(OWNER, 'owner'),
      ['clubs/' + SERVER + '/members/' + MEMBER]: member(MEMBER, 'member'),
      ['clubs/' + SERVER + '/channels/' + CHANNEL]: channel(),
      ['clubs/' + SERVER + '/channels/' + CHANNEL + '/files/' + FILE_ID]: file(),
      ['serverCompanyFileUploadReservations/' + FILE_ID]: reservation(),
    };
    for (const [location, value] of Object.entries(entries)) {
      await setDoc(doc(db, location), value);
    }
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid) {
  return env.authenticatedContext(uid, { email_verified: true });
}

test('Company File feed query has its committed composite index', () => {
  const indexes = JSON.parse(fs.readFileSync(
    path.join(__dirname, '../firestore.indexes.json'),
    'utf8',
  )).indexes;
  assert.ok(indexes.some((index) =>
    index.collectionGroup === 'files' &&
    index.queryScope === 'COLLECTION' &&
    JSON.stringify(index.fields) === JSON.stringify([
      { fieldPath: 'status', order: 'ASCENDING' },
      { fieldPath: 'createdAt', order: 'DESCENDING' },
    ])));
});

test('Company File descriptors follow exact channel ACL and remain callable written', async () => {
  const filePath = 'clubs/' + SERVER + '/channels/' + CHANNEL + '/files/' + FILE_ID;
  await assertSucceeds(getDoc(doc(context(MEMBER).firestore(), filePath)));
  const rows = await assertSucceeds(getDocs(query(
    collection(context(MEMBER).firestore(), 'clubs/' + SERVER + '/channels/' + CHANNEL + '/files'),
    where('status', '==', 'published'),
    orderBy('createdAt', 'desc'),
  )));
  assert.deepEqual(rows.docs.map((row) => row.id), [FILE_ID]);
  await assertFails(getDoc(doc(context(OUTSIDER).firestore(), filePath)));
  for (const uid of [OWNER, MEMBER, OUTSIDER]) {
    const reference = doc(context(uid).firestore(), filePath);
    await assertFails(setDoc(reference, file()));
    await assertFails(updateDoc(reference, { displayName: 'forged.pdf' }));
    await assertFails(deleteDoc(reference));
  }
});

test('only the exact reserved immutable Company File object can be uploaded', async () => {
  await env.clearStorage();
  const ownerStorage = context(OWNER).storage(PROJECT);
  await assertSucceeds(uploadBytes(
    ref(ownerStorage, FILE_PATH),
    FILE_BYTES,
    { contentType: 'application/pdf', customMetadata: metadata() },
  ));
  await assertFails(uploadBytes(
    ref(ownerStorage, FILE_PATH),
    FILE_BYTES,
    { contentType: 'application/pdf', customMetadata: metadata() },
  ));
  await assertFails(deleteObject(ref(ownerStorage, FILE_PATH)));
  await assertFails(listAll(ref(ownerStorage,
    'server_company_files/' + SERVER + '/' + CHANNEL + '/' + OWNER)));
});

test('Company File upload rejects wrong owner, metadata, type, size and canonical path', async () => {
  await env.clearStorage();
  const ownerStorage = context(OWNER).storage(PROJECT);
  const memberStorage = context(MEMBER).storage(PROJECT);
  await assertFails(uploadBytes(
    ref(memberStorage,
      'server_company_files/' + SERVER + '/' + CHANNEL + '/' + MEMBER + '/' + FILE_ID + '.pdf'),
    FILE_BYTES,
    { contentType: 'application/pdf', customMetadata: metadata() },
  ));
  await assertFails(uploadBytes(
    ref(ownerStorage, FILE_PATH + '.pdf'),
    FILE_BYTES,
    { contentType: 'application/pdf', customMetadata: metadata() },
  ));
  await assertFails(uploadBytes(
    ref(ownerStorage, FILE_PATH),
    FILE_BYTES,
    { contentType: 'application/pdf', customMetadata: metadata({ forged: 'true' }) },
  ));
  await assertFails(uploadBytes(
    ref(ownerStorage, FILE_PATH),
    FILE_BYTES,
    { contentType: 'text/plain', customMetadata: metadata() },
  ));
  await assertFails(uploadBytes(
    ref(ownerStorage, FILE_PATH),
    Buffer.concat([FILE_BYTES, Buffer.from('x')]),
    { contentType: 'application/pdf', customMetadata: metadata() },
  ));
});

test('direct Company File read exists only for its owner while reservation is live', async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(
      ref(ctx.storage(PROJECT), FILE_PATH),
      FILE_BYTES,
      { contentType: 'application/pdf', customMetadata: metadata() },
    );
  });
  const ownerRef = ref(context(OWNER).storage(PROJECT), FILE_PATH);
  await assertSucceeds(getBytes(ownerRef));
  await assertFails(getBytes(ref(context(MEMBER).storage(PROJECT), FILE_PATH)));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'serverCompanyFileUploadReservations/' + FILE_ID));
  });
  await assertFails(getBytes(ownerRef));
});
