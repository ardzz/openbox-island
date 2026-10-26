# tests/ytm/bridge-authority.bats: tab authority uses real background relay events.
load ../helpers

@test "playing tab wins over paused heartbeats and closing it promotes the remaining tab" {
  run node - "$REPO/browser/ytm-bridge" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const dir = process.argv[2];
let message, removed;
const forwarded = [];
const context = vm.createContext({
  chrome: {
    runtime: {
      onMessage: { addListener(fn) { message = fn; } },
      connectNative() {
        return { onDisconnect: { addListener() {} }, postMessage(payload) { forwarded.push(payload); } };
      },
    },
    tabs: { onRemoved: { addListener(fn) { removed = fn; } } },
  },
});
context.importScripts = file => vm.runInContext(fs.readFileSync(`${dir}/${file}`, 'utf8'), context);
vm.runInContext(fs.readFileSync(`${dir}/background.js`, 'utf8'), context);
const send = (id, title, playing, ts) => message({ title, playing, ts }, {
  tab: { id }, url: 'https://music.youtube.com/',
});
send(2, 'B', false, 1);
assert.equal(forwarded.at(-1).title, 'B', 'a lone paused reporter is authoritative');
send(1, 'A', true, 2);
send(2, 'B', false, 3);
assert.equal(forwarded.at(-1).title, 'A', 'paused B must not overwrite playing A');
assert.equal(forwarded.at(-1).ts, 2, 'B must not refresh the timestamp of A');
send(1, 'A', false, 4);
send(2, 'B', false, 5);
assert.equal(forwarded.at(-1).title, 'A', 'most recently paused A retains authority');
removed(1);
assert.equal(forwarded.at(-1).title, 'B', 'closing A promotes B');
JS
  [ "$status" -eq 0 ]
}

@test "navigation gone removes authority and stale playing reporters cannot suppress live paused tabs" {
  run node - "$REPO/browser/ytm-bridge" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const dir = process.argv[2];
let message, now = 1000;
const forwarded = [];
const context = vm.createContext({
  Date: { now: () => now },
  chrome: {
    runtime: {
      onMessage: { addListener(fn) { message = fn; } },
      connectNative() {
        return { onDisconnect: { addListener() {} }, postMessage(payload) { forwarded.push(payload); } };
      },
    },
    tabs: { onRemoved: { addListener() {} } },
  },
});
context.importScripts = file => vm.runInContext(fs.readFileSync(`${dir}/${file}`, 'utf8'), context);
vm.runInContext(fs.readFileSync(`${dir}/background.js`, 'utf8'), context);
const send = (id, payload) => message(payload, { tab: { id }, url: 'https://music.youtube.com/' });
send(1, { title: 'A', playing: true, ts: now });
send(2, { title: 'B', playing: true, ts: now });
send(2, { title: 'B', playing: false, ts: now });
send(1, { gone: true });
assert.equal(forwarded.at(-1).title, 'B', 'navigation away promotes B');
assert.equal(forwarded.at(-1).playing, false);
send(1, { title: 'A', playing: true, ts: now });
now += 10000;
send(2, { title: 'B', playing: false, ts: now });
assert.equal(forwarded.at(-1).title, 'A', 'reporter remains valid at ten seconds');
now += 1;
send(2, { title: 'B', playing: false, ts: now });
assert.equal(forwarded.at(-1).title, 'B', 'expired ghost cannot suppress B');
JS
  [ "$status" -eq 0 ]
}
