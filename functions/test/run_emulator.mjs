import { mkdtemp, copyFile, writeFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
const functions = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const temp = await mkdtemp(join(tmpdir(), 'recall-firebase-emulator-'));
try {
  await copyFile(join(functions, '../firestore.rules'), join(temp, 'firestore.rules'));
  await copyFile(join(functions, '../firestore.indexes.json'), join(temp, 'firestore.indexes.json'));
  await writeFile(join(temp, 'firebase.json'), JSON.stringify({ firestore: { rules: 'firestore.rules', indexes: 'firestore.indexes.json' }, emulators: { firestore: { host: '127.0.0.1', port: 18080 }, auth: { host: '127.0.0.1', port: 19099 }, ui: { enabled: false }, hub: { host: '127.0.0.1', port: 14400 }, logging: { host: '127.0.0.1', port: 14500 }, singleProjectMode: true } }));
  const env = { ...process.env };
  if (!env.JAVA_HOME) {
    const jbr = '/Applications/Android Studio.app/Contents/jbr/Contents/Home';
    try { await access(join(jbr, 'bin/java')); env.JAVA_HOME = jbr; env.PATH = `${jbr}/bin:${env.PATH}`; } catch { /* Use configured Java. */ }
  }
  const child = spawn('firebase', ['emulators:exec', '--config', join(temp, 'firebase.json'), '--only', 'firestore,auth', '--project', 'demo-recall-backend', 'npx --yes node@22 --test --test-concurrency=1 test/*.test.mjs'], { cwd: functions, env, stdio: 'inherit' });
  const stop = () => child.kill('SIGINT');
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
  const code = await new Promise((accept, reject) => { child.once('error', reject); child.once('exit', value => accept(value ?? 1)); });
  process.exitCode = code;
} finally { await rm(temp, { recursive: true, force: true }); }
