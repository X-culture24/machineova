import http from 'node:http';
const first=['Leah','Baraka','Jepkosgei','Hassan','Nekesa','Imani','Otieno','Musa','Kamau','Zawadi','Esther','Faith','Chebet','Daudi','Wanjiru'];
const last=['Example','Placeholder','Sample','Demo'];
const villages=['Kapsogo','Benin','Kaptui','Kapsoo','Mongo','Kipsubech','Kapkong','Borowonin'];
const subs=['Barowonin','Benin','Borokonin','Boronnin','Borowin'];
const people=[]; for(let i=0;i<1285;i++){people.push({national_id:String(20000000+((i*7919)%9999999)).padStart(8,'2'),full_name:`${first[i%15]} ${last[(i*3)%4]}`.toUpperCase(),father_name:`${first[(i+5)%15]} ${last[(i+1)%4]}`.toUpperCase(),family_name:`${first[(i+9)%15]} ${last[(i+2)%4]}`.toUpperCase(),county:'BARINGO',district:'BARINGO CENTRAL',division:'KABARNET',location:'KAPROPITA',sub_location:subs[i%5].toUpperCase(),village:villages[i%8].toUpperCase(),family:['KIMUTAI','KIPROP','CHERUIYOT','KIBET'][(i*5)%4]});}
const user={id:1,username:'sample.clerk',full_name:'Sample Clerk'};
const send=(res,code,obj)=>{res.writeHead(code,{'content-type':'application/json','access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'*'});res.end(JSON.stringify(obj));};
const match=(p,q)=>{const ws=q.toLowerCase().split(/\s+/).filter(Boolean);const s=Object.values(p).join(' ').toLowerCase();return ws.every(w=>s.includes(w));};
const app=(req,res)=>{if(req.method==='OPTIONS')return send(res,204,{});let body='';req.on('data',c=>body+=c);req.on('end',()=>{
 const u=new URL(req.url,'http://x'); const p=u.pathname.replace(/^\/api\/iebc\//,'');
 if(u.pathname.startsWith('/api/field/demo-login')) return send(res,410,{error:{code:'GONE',message:'off'}});
 if(p==='login/'){const b=JSON.parse(body||'{}'); if(b.password!=='correct') return send(res,401,{error:{code:'INVALID_CREDENTIALS',message:'Invalid credentials'}}); return send(res,200,{access_token:'a',refresh_token:'r',user});}
 if(p==='refresh/') return send(res,200,{access_token:'a'});
 if(p==='logout/') return send(res,200,{success:true});
 if(p==='me/') return send(res,200,{...user,areas:[{county:'BARINGO',district:'BARINGO CENTRAL',division:'KABARNET',location:'KAPROPITA'}],unregistered_total:people.length});
 const q=u.searchParams.get('q')||'';
 if(p==='suggest/') return send(res,200,{results:people.filter(x=>match(x,q)).slice(0,6)});
 if(p==='voters/'){const page=+u.searchParams.get('page')||1,ps=+u.searchParams.get('page_size')||25;const all=q?people.filter(x=>match(x,q)):people;const r=all.slice((page-1)*ps,page*ps);return send(res,200,{count:all.length,next:page*ps<all.length?'n':null,previous:page>1?'p':null,results:r});}
 if(p.startsWith('lookup/')){const id=u.searchParams.get('id');
   if(id==='30000001') return send(res,200,{national_id:id,full_name:'GRACE SAMPLE',father_name:'PETER SAMPLE',family_name:'KAMAU EXAMPLE',county:'BARINGO',district:'BARINGO CENTRAL',division:'KABARNET',location:'KAPROPITA',sub_location:'BENIN',village:'KAPTUI',family:'KIPROP',registration_status:'REGISTERED'});
   const x=people.find(v=>v.national_id===id); if(x) return send(res,200,{...x,registration_status:'NOT_REGISTERED'});
   return send(res,404,{error:{code:'NOT_FOUND',message:`No one with ID ${id} was found in your area.`}});}
 if(p.startsWith('areas/')) return send(res,200,{level:'x',values:[]});
 send(res,404,{error:{code:'NOT_FOUND',message:'not found'}});
});};
http.createServer(app).listen(8000,'127.0.0.1');http.createServer(app).listen(18000,'127.0.0.1',()=>console.log('mock up'));
