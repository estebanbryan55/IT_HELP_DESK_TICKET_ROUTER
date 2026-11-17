// Removes bearer tokens from saved Postman run files (JSON-in-JSON excerpts).
//   node tools/redact-evidence.mjs evidence/02-baseline-postman-run.json ...
import { readFileSync, writeFileSync } from 'node:fs';

for (const file of process.argv.slice(2)) {
  const run = JSON.parse(readFileSync(file, 'utf8'));
  let count = 0;
  for (const r of run.results) {
    r.responseExcerpt = r.responseExcerpt.replace(/"token":"[^"]*"?/g, () => {
      count++;
      return '"token":"[REDACTED]"';
    });
  }
  writeFileSync(file, JSON.stringify(run, null, 2));
  console.log(`${file}: ${count} token(s) redacted`);
}
