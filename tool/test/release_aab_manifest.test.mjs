// node --test tool/test/release_aab_manifest.test.mjs
//
// The protobuf AndroidManifest decoder that gates versionCode before a Play
// upload. Fixtures are encoded here in the aapt2 XmlNode shape. The decoder
// was also checked by hand against the retained 3.0.0 (34) and 2.0.0 (33)
// bundles, which carry versionCode both as a raw string and as a compiled
// integer, exactly like the "both" fixture below.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { checkManifest, decodeManifest, readFields } from '../release/aab_manifest.mjs';

const ANDROID = 'http://schemas.android.com/apk/res/android';

function varint(value) {
  let number = BigInt(value);
  if (number < 0n) number = BigInt.asUintN(64, number);
  const bytes = [];
  do {
    let byte = Number(number & 0x7fn);
    number >>= 7n;
    if (number > 0n) byte |= 0x80;
    bytes.push(byte);
  } while (number > 0n);
  return Buffer.from(bytes);
}

const bytesField = (field, payload) => {
  const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
  return Buffer.concat([varint((field << 3) | 2), varint(body.length), body]);
};
const varintField = (field, value) => Buffer.concat([varint(field << 3), varint(value)]);

function attribute({ namespace = '', name, raw, compiledInt, compiledString }) {
  const parts = [];
  if (namespace) parts.push(bytesField(1, namespace));
  parts.push(bytesField(2, name));
  if (raw !== undefined) parts.push(bytesField(3, raw));
  if (compiledInt !== undefined) {
    parts.push(bytesField(6, bytesField(7, varintField(6, compiledInt))));
  } else if (compiledString !== undefined) {
    parts.push(bytesField(6, bytesField(2, bytesField(1, compiledString))));
  }
  return bytesField(4, Buffer.concat(parts));
}

function manifest(attributes, rootName = 'manifest') {
  const element = Buffer.concat([bytesField(3, rootName), ...attributes.map(attribute)]);
  // A source position (field 3 of XmlNode) and a fixed32 field exercise the skipping paths.
  const source = bytesField(3, varintField(1, 7));
  return Buffer.concat([bytesField(1, element), source, Buffer.from([(9 << 3) | 5, 1, 2, 3, 4])]);
}

const standard = [
  { name: 'package', raw: 'app.yovoice' },
  { namespace: ANDROID, name: 'versionCode', raw: '36', compiledInt: 36 },
  { namespace: ANDROID, name: 'versionName', raw: '3.0.0' },
];

test('decodes raw and compiled values the way real bundles carry them', () => {
  assert.deepEqual(decodeManifest(manifest(standard)), {
    package: 'app.yovoice',
    versionCode: '36',
    versionName: '3.0.0',
  });
});

test('decodes a compiled-only versionCode and a compiled string versionName', () => {
  const decoded = decodeManifest(
    manifest([
      { name: 'package', raw: 'app.yovoice' },
      { namespace: ANDROID, name: 'versionCode', compiledInt: 2100000000 },
      { namespace: ANDROID, name: 'versionName', compiledString: '3.1.0' },
    ]),
  );
  assert.equal(decoded.versionCode, '2100000000');
  assert.equal(decoded.versionName, '3.1.0');
});

test('refuses a manifest whose raw and compiled versionCode disagree', () => {
  assert.throws(
    () =>
      decodeManifest(
        manifest([{ namespace: ANDROID, name: 'versionCode', raw: '36', compiledInt: 35 }]),
      ),
    /disagrees/u,
  );
});

test('ignores a versionCode outside the android namespace', () => {
  const decoded = decodeManifest(
    manifest([
      { name: 'versionCode', raw: '99' },
      { namespace: ANDROID, name: 'versionCode', raw: '36', compiledInt: 36 },
    ]),
  );
  assert.equal(decoded.versionCode, '36');
});

test('refuses a document that is not a manifest, and truncated input', () => {
  assert.throws(() => decodeManifest(manifest(standard, 'application')), /expected <manifest>/u);
  const whole = manifest(standard);
  assert.throws(() => decodeManifest(whole.subarray(0, whole.length - 30)), /Truncated/u);
  assert.throws(() => readFields(Buffer.from([0x0b])), /wire type/u);
});

test('checkManifest reports every mismatch', () => {
  const decoded = { package: 'app.other', versionCode: '35', versionName: '2.0.0' };
  const problems = checkManifest(decoded, {
    expectPackage: 'app.yovoice',
    expectVersionCode: '36',
    expectVersionName: '3.0.0',
  });
  assert.equal(problems.length, 3);
  assert.deepEqual(
    checkManifest(decodeManifest(manifest(standard)), {
      expectPackage: 'app.yovoice',
      expectVersionCode: '36',
      expectVersionName: '3.0.0',
    }),
    [],
  );
});
