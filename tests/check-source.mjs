import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url), lua=require('luaparse'), acorn=require('acorn');
const root=path.resolve(new URL('..',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).filter(e=>!['node_modules','.git','artifacts','local'].includes(e.name)).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
let count=0;
for(const file of walk(path.join(root,'openwrt'))){
 const text=fs.readFileSync(file,'utf8');
 if(file.endsWith('.lua')){lua.parse(text,{luaVersion:'5.1'});count++;}
 if(file.endsWith('.js')) acorn.parse(text,{ecmaVersion:5});
 if(file.endsWith('.htm')){
  for(const match of text.replace(/<%[\s\S]*?%>/g,'TEMPLATE').matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)) acorn.parse(match[1],{ecmaVersion:5});
  assert(!/innerHTML\s*=|localStorage|sessionStorage/.test(text),'Do not render untrusted state as HTML or persist private profiles in the browser');
 }
 assert(!/-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----/.test(text),'Do not bundle private keys');
 if(file.endsWith('.js')) assert(!/innerHTML\s*=|localStorage|sessionStorage/.test(text),'Do not render untrusted state as HTML or store profiles in the browser');
}
const controller=fs.readFileSync(path.join(root,'openwrt/luasrc/controller/easytier_home_game.lua'),'utf8');
assert(controller.includes('test_post_security()')&&controller.includes("'POST'"),'Mutations require LuCI CSRF-protected POST');
assert(controller.includes("'admin','vpn','easytier','home_game'"),'Extend the existing EasyTier menu');
const model=fs.readFileSync(path.join(root,'openwrt/luasrc/model/easytier_home_game.lua'),'utf8');
assert(model.includes('within(rule.source,cfg.game_cidr)'),'Device scope must stay within the accelerated network');
assert(model.includes('pcall(M.rollback,backup.id)'),'Failed application must attempt a scoped restore');
assert(controller.includes("'ubus call service add '")&&controller.includes('SIGALRM'),'Start timed probes through procd, not the CGI signal environment');
assert(controller.includes('return {download=data}')&&controller.includes('http.write(result.download)'),'Send private downloads outside the Lua 5.1 protected operation');
for(const file of walk(root)){
 if(!/\.(md|lua|sh|htm|json|uci|yml)$/.test(file))continue;
 const source=fs.readFileSync(file,'utf8');
 if(file===path.join(root,'tests/check-source.mjs'))continue;
 assert(!/-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----|https?:\/\/root:[^@\s]+@/.test(source),'Private credentials in public repository');
}
for(const file of ['README.md','AGENTS.md','docs/DEPLOY.md','docs/COMPATIBILITY.md','docs/ACCEPTANCE.md','docs/NODES.md']) assert(fs.existsSync(path.join(root,file)),file);
console.log(`PASS: ${count} Lua 5.1 sources, ES5 panel, menu/CSRF/scope checks and public source privacy checks`);
