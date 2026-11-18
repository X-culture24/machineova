import { spawn } from 'node:child_process';
import fs from 'node:fs';
const OUT=process.argv[2], PROFILE=process.argv[3];
const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--remote-debugging-port=9333',`--user-data-dir=${PROFILE}`,'--no-first-run','--hide-scrollbars','about:blank'],{stdio:'ignore'});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let tabs; for(let i=0;i<40;i++){try{tabs=await (await fetch('http://127.0.0.1:9333/json')).json(); if(tabs.find(t=>t.type==='page'))break;}catch{} await sleep(250);}
const ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
await new Promise(r=>ws.onopen=r);
let id=0; const pend={};
ws.onmessage=e=>{const m=JSON.parse(e.data); if(m.id&&pend[m.id]){pend[m.id](m); delete pend[m.id];}};
const cmd=(method,params={})=>new Promise(r=>{const i=++id; pend[i]=r; ws.send(JSON.stringify({id:i,method,params}));});
const ev=async(expr)=>(await cmd('Runtime.evaluate',{expression:expr,awaitPromise:true,returnByValue:true})).result?.result?.value;
const RECTS={};
const rectJS=`window.__r=(k,a)=>{let e=null;
 if(k==='sel'){e=document.querySelector(a);}
 else if(k==='root'){e=document.querySelector(a); e=e&&(e.closest('.MuiOutlinedInput-root')||e.closest('.MuiInputBase-root')||e);}
 else if(k==='btn'){e=[...document.querySelectorAll('button')].find(b=>b.textContent.trim()===a);}
 else if(k==='aria'){e=document.querySelector('[aria-label="'+a+'"]');}
 else if(k==='text'){const all=[...document.querySelectorAll('body *')].filter(x=>x.children.length===0||[...x.childNodes].some(n=>n.nodeType===3&&n.textContent.trim()));e=all.find(x=>x.textContent.trim().startsWith(a));}
 if(!e)return null;const r=e.getBoundingClientRect();const d=window.devicePixelRatio;return [r.left*d,r.top*d,r.right*d,r.bottom*d];}`;
const shot=async(name,marks={})=>{await ev(rectJS); const m={}; for(const [k,[kind,arg]] of Object.entries(marks)) m[k]=await ev(`window.__r(${JSON.stringify(kind)},${JSON.stringify(arg)})`); RECTS[name]=m; fs.writeFileSync(`${OUT}/rects.json`,JSON.stringify(RECTS,null,1)); await sleep(700); const r=await cmd('Page.captureScreenshot',{format:'png'}); fs.writeFileSync(`${OUT}/${name}.png`,Buffer.from(r.result.data,'base64')); console.log('shot',name);};
const type=async(sel,text)=>{await ev(`(()=>{const e=document.querySelector(${JSON.stringify(sel)}); e.focus(); e.select&&e.select(); return !!e})()`); await cmd('Input.insertText',{text});};
const enter=()=>Promise.all(['keyDown','keyUp'].map(t=>cmd('Input.dispatchKeyEvent',{type:t,key:'Enter',code:'Enter',windowsVirtualKeyCode:13,text:t==='keyDown'?'\r':undefined})));
const clickText=(t)=>ev(`(()=>{const b=[...document.querySelectorAll('button')].find(b=>b.textContent.trim()===${JSON.stringify(t)}); b&&b.click(); return !!b})()`);
const go=async(url)=>{await cmd('Page.navigate',{url}); await sleep(2500);};
const metrics=(w,h,mobile,dpr)=>cmd('Emulation.setDeviceMetricsOverride',{width:w,height:h,deviceScaleFactor:dpr,mobile});
await cmd('Page.enable'); await cmd('Runtime.enable');
await cmd('Emulation.setTimezoneOverride',{timezoneId:'Africa/Nairobi'});
await cmd('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:'light'}]});
const B='http://localhost:5190';
const people0=String(20000000).padStart(8,'2');
for (const [tag,w,h,mob,dpr] of [['phone',390,844,true,2],['desktop',1366,860,false,1]]) {
  await metrics(w,h,mob,dpr);
  await go(B+'/iebc/login'); await ev('localStorage.clear()'); await go(B+'/iebc/login');
  await shot(`${tag}_01_login`,{1:['root','input:not([type="password"])'],2:['root','input[type="password"]'],3:['sel','button[aria-label$="password"]'],4:['btn','Sign in']});
  await type('input[name="username"], input[autocomplete="username"], input[type="text"]','sample.clerk');
  await type('input[type="password"]','wrong-password');
  await clickText('Sign in'); await sleep(1500);
  await shot(`${tag}_02_login_error`,{1:['text','Wrong username']});
  await type('input[type="password"]','correct');
  await clickText('Sign in'); await sleep(2500);
  await shot(`${tag}_03_list`,{1:['text','Your location'],2:['text','1,285'],3:['root','input[placeholder^="Search"]'],4:['btn','Search'],5:['sel','table'],6:['aria','Sign out']});
  await type('input[placeholder^="Search"]','chebet'); await sleep(1800);
  await shot(`${tag}_04_suggest`,{1:['root','input[placeholder^="Search"]'],2:['sel','[role="listbox"]']});
  await enter(); await sleep(1500);
  await ev('document.activeElement.blur()'); await sleep(300);
  await shot(`${tag}_05_results`,{1:['text','257 matching'],2:['btn','Clear']});
  await ev('window.scrollTo(0, document.body.scrollHeight)'); await sleep(600);
  await shot(`${tag}_06_bottom`,{1:['text',tag==='phone'?'Per page':'Rows per page'],2:['sel','.MuiTablePagination-displayedRows'],3:['aria','Go to next page'],4:['text','Signed in as']});
  await ev('window.scrollTo(0,0)'); await sleep(400);
  const LK='input[inputmode="numeric"]';
  await type(LK, people0); await clickText('Check'); await sleep(1500); await ev('document.activeElement.blur()');
  await ev(`document.querySelector('${LK}').scrollIntoView({block:'start'}); window.scrollBy(0,-90)`); await sleep(500);
  await shot(`${tag}_07_lookup_not`,{1:['root',LK],2:['btn','Check'],3:['text','Not registered']});
  await type(LK,'30000001'); await clickText('Check'); await sleep(1500); await ev('document.activeElement.blur()');
  await shot(`${tag}_08_lookup_reg`,{1:['text','Registered']});
  await type(LK,'12345678'); await clickText('Check'); await sleep(1500); await ev('document.activeElement.blur()');
  await shot(`${tag}_09_lookup_none`,{1:['text','No one with ID']});
  await clickText('Clear'); await ev('window.scrollTo(0,0)');
}
ws.close(); chrome.kill();
