// Reads package, versionCode and versionName from an Android App Bundle's
// base/manifest/AndroidManifest.xml, which aapt2 stores as a protobuf XmlNode
// (frameworks/base/tools/aapt2/Resources.proto), not as text or binary XML.
//
// Build rounds on the Mac had no bundletool or aapt2 and used a local decoder
// for the same reason; this is that check made reproducible and dependency
// free. Extract the entry first (`unzip -p app.aab base/manifest/AndroidManifest.xml`)
// and pass the file:
//
//   node aab_manifest.mjs --manifest FILE --expect-package app.yovoice \
//     --expect-version-code 36 --expect-version-name 3.0.0

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import { ReleaseError, parseArgs, requireArg, runCli } from './lib.mjs';

const ANDROID_NAMESPACE = 'http://schemas.android.com/apk/res/android';

function readVarint(buffer, state) {
  let result = 0n;
  let shift = 0n;
  for (;;) {
    if (state.offset >= buffer.length) throw new ReleaseError('Truncated protobuf varint');
    const byte = buffer[state.offset];
    state.offset += 1;
    result |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return result;
    shift += 7n;
    if (shift > 63n) throw new ReleaseError('Protobuf varint is too long');
  }
}

// Returns [{ field, wire, value }] where value is a Buffer for length-delimited
// fields and a BigInt for varints. Fixed-width fields are skipped.
export function readFields(buffer) {
  const fields = [];
  const state = { offset: 0 };
  while (state.offset < buffer.length) {
    const key = readVarint(buffer, state);
    const field = Number(key >> 3n);
    const wire = Number(key & 7n);
    if (wire === 0) {
      fields.push({ field, wire, value: readVarint(buffer, state) });
    } else if (wire === 2) {
      const length = Number(readVarint(buffer, state));
      if (state.offset + length > buffer.length) throw new ReleaseError('Truncated protobuf field');
      fields.push({ field, wire, value: buffer.subarray(state.offset, state.offset + length) });
      state.offset += length;
    } else if (wire === 1) {
      state.offset += 8;
    } else if (wire === 5) {
      state.offset += 4;
    } else {
      throw new ReleaseError(`Unsupported protobuf wire type ${wire}`);
    }
    if (state.offset > buffer.length) throw new ReleaseError('Truncated protobuf message');
  }
  return fields;
}

function stringField(fields, number) {
  const found = fields.find((entry) => entry.field === number && entry.wire === 2);
  return found ? found.value.toString('utf8') : '';
}

function messageField(fields, number) {
  const found = fields.find((entry) => entry.field === number && entry.wire === 2);
  return found ? readFields(found.value) : null;
}

// XmlAttribute: namespace_uri=1, name=2, value=3, resource_id=5, compiled_item=6.
// Item: str=2 (String.value=1), raw_str=3 (RawString.value=1), prim=7.
// Primitive: int_decimal_value=6, int_hexadecimal_value=7.
//
// Real bundles (builds 33 and 34) carry versionCode twice: the raw string and a
// compiled integer primitive. The compiled value is what Android and Play
// read, so it wins, and a disagreement between the two is refused.
function attributeValue(attributeFields) {
  const raw = stringField(attributeFields, 3);
  const item = messageField(attributeFields, 6);
  let compiled = '';
  if (item) {
    const primitive = messageField(item, 7);
    const integer = primitive?.find((entry) => (entry.field === 6 || entry.field === 7) && entry.wire === 0);
    if (integer) {
      compiled = BigInt.asIntN(32, integer.value).toString();
    } else {
      for (const number of [2, 3]) {
        const text = messageField(item, number);
        if (text) {
          compiled = stringField(text, 1);
          break;
        }
      }
    }
  }
  if (raw !== '' && compiled !== '' && raw !== compiled) {
    throw new ReleaseError(`Manifest attribute disagrees with itself: raw "${raw}", compiled "${compiled}"`);
  }
  return compiled !== '' ? compiled : raw;
}

export function decodeManifest(buffer) {
  const root = readFields(buffer);
  const element = messageField(root, 1);
  if (!element) throw new ReleaseError('Manifest has no root element');
  const name = stringField(element, 3);
  if (name !== 'manifest') throw new ReleaseError(`Manifest root element is <${name}>, expected <manifest>`);
  const result = { package: '', versionCode: '', versionName: '' };
  for (const entry of element) {
    if (entry.field !== 4 || entry.wire !== 2) continue;
    const attribute = readFields(entry.value);
    const namespace = stringField(attribute, 1);
    const attributeName = stringField(attribute, 2);
    if (attributeName === 'package' && namespace === '') {
      result.package = attributeValue(attribute);
    } else if (attributeName === 'versionCode' && namespace === ANDROID_NAMESPACE) {
      result.versionCode = attributeValue(attribute);
    } else if (attributeName === 'versionName' && namespace === ANDROID_NAMESPACE) {
      result.versionName = attributeValue(attribute);
    }
  }
  return result;
}

export function checkManifest(decoded, { expectPackage, expectVersionCode, expectVersionName }) {
  const problems = [];
  if (decoded.package !== expectPackage) problems.push(`package is "${decoded.package}", expected "${expectPackage}"`);
  if (decoded.versionCode !== expectVersionCode) {
    problems.push(`versionCode is "${decoded.versionCode}", expected "${expectVersionCode}"`);
  }
  if (decoded.versionName !== expectVersionName) {
    problems.push(`versionName is "${decoded.versionName}", expected "${expectVersionName}"`);
  }
  return problems;
}

export async function main(argv) {
  const args = parseArgs(argv);
  const decoded = decodeManifest(readFileSync(requireArg(args, 'manifest')));
  const problems = checkManifest(decoded, {
    expectPackage: requireArg(args, 'expect-package', /^[A-Za-z0-9_.]+$/u),
    expectVersionCode: requireArg(args, 'expect-version-code', /^[1-9][0-9]*$/u),
    expectVersionName: requireArg(args, 'expect-version-name', /^[0-9]+\.[0-9]+\.[0-9]+$/u),
  });
  process.stdout.write(
    `AAB manifest: package=${decoded.package} versionCode=${decoded.versionCode} versionName=${decoded.versionName}\n`,
  );
  if (problems.length > 0) {
    throw new ReleaseError(`AAB manifest check failed: ${problems.join('; ')}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  await runCli(main);
}
