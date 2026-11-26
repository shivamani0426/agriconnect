import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
const policy=readFileSync(new URL('../public/privacy.html',import.meta.url),'utf8');
test('public static policy describes current data handling and contact',()=>{for(const term of ['Privacy policy','WhatsApp test integration','deletion requests','AgriConnect project contact page','simulated','issue tracker is public'])assert.ok(policy.includes(term),term);assert.doesNotMatch(policy,/<script\b/i);});
test('website links to public policy',()=>assert.match(readFileSync(new URL('../src/main.tsx',import.meta.url),'utf8'),/href="\/privacy\.html"/));
