// Execute both embedded Apps Script templates with mock Google services.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
for (const name of ['xrv-install.sh', 'xrv-client.sh']) {
  const script = fs.readFileSync(path.join(__dirname, '..', name), 'utf8')
    .split("<<'CODE_EOF'\n")[1].split('\nCODE_EOF')[0]
    .replace('RELAY_URL_PLACEHOLDER', 'https://vpn.example.com:10443/tunnel');
  let status = 200, throws = false, calls = 0;
  const context = vm.createContext({
    UrlFetchApp: {fetch(url, options) {
      calls++;
      assert.equal(url, 'https://vpn.example.com:10443/tunnel');
      assert.equal(options.payload, 'opaque encrypted payload');
      assert.equal(options.validateHttpsCertificates, true);
      assert.equal(options.followRedirects, false);
      assert.equal('deadline' in options, false);
      if (throws) throw new Error('PRIVATE_EXCEPTION');
      return {getResponseCode: () => status, getContentText: () => 'PRIVATE_BODY'};
    }},
    ContentService: {
      MimeType: {TEXT: 'text', JSON: 'json'},
      createTextOutput(text) {return {text, setMimeType() {return this;}};}
    },
    Utilities: {formatDate: () => '2026-11-15'},
    PropertiesService: {getScriptProperties() {throw new Error('Unexpected storage access');}}
  });
  vm.runInContext(script, context);
  assert.equal(context.doPost({postData: {contents: 'opaque encrypted payload'}}).text, 'PRIVATE_BODY');
  status = 503;
  assert.throws(() => context.doPost({postData: {contents: 'opaque encrypted payload'}}),
    e => e.message === 'upstream status 503');
  throws = true;
  assert.throws(() => context.doPost({postData: {contents: 'opaque encrypted payload'}}),
    e => !/PRIVATE/.test(e.message) && /fetch failed/.test(e.message));
  assert.equal(calls, 3, 'No automatic replay of failed POST requests');
  const health = JSON.parse(context.doGet({}).text);
  assert.equal(health.ok, true);
  assert.equal(health.protocol, 1);
  assert.equal(health.count, 0);
  console.log(name + ': forwarding, TLS options, sanitized errors and health passed');
}
