// Production start: apply pending database migrations, then boot the server.
//
// `prisma migrate deploy` needs DIRECT_DATABASE_URL (schema.prisma's
// directUrl): a non-pooled connection, since migrations don't work reliably
// through a connection pooler. If the host didn't set it, derive it from
// DATABASE_URL instead of refusing to start — on Neon the direct host is the
// pooled host without "-pooler", and for any other Postgres host the same URL
// is used as-is. An explicitly set DIRECT_DATABASE_URL always wins.
const { spawnSync } = require('node:child_process');
const path = require('node:path');

if (!process.env.DIRECT_DATABASE_URL && process.env.DATABASE_URL) {
  try {
    const url = new URL(process.env.DATABASE_URL);
    url.hostname = url.hostname.replace('-pooler', '');
    process.env.DIRECT_DATABASE_URL = url.toString();
    console.log(
      `DIRECT_DATABASE_URL not set — using DATABASE_URL's host (${url.hostname}) for migrations.`,
    );
  } catch {
    process.env.DIRECT_DATABASE_URL = process.env.DATABASE_URL;
  }
}

const prismaCli = require.resolve('prisma/build/index.js');
const migrate = spawnSync(process.execPath, [prismaCli, 'migrate', 'deploy'], {
  stdio: 'inherit',
  env: process.env,
});
if (migrate.status !== 0) {
  // Same behavior as before: a failed migration stops the boot, so the host
  // keeps the previous working version running.
  process.exit(migrate.status ?? 1);
}

require(path.join(__dirname, '..', 'dist', 'src', 'index.js'));
