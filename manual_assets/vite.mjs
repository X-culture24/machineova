const F='/Users/lawrence/Documents/sdics.tech/frontend';
const { createServer } = await import(F+'/node_modules/vite/dist/node/index.js');
const react = (await import(F+'/node_modules/@vitejs/plugin-react/dist/index.js')).default;
const a = (p)=>F+'/src'+p;
const server = await createServer({ configFile:false, define:{'import.meta.env.VITE_API_URL':'"/api"'}, envDir:'/Users/lawrence/machinenova/manual_assets/envdir', root:F, cacheDir:process.argv[2], plugins:[react()],
  resolve:{alias:{'@':a(''),'@components':a('/components'),'@pages':a('/pages'),'@layouts':a('/layouts'),'@features':a('/features'),'@services':a('/services'),'@hooks':a('/hooks'),'@types':a('/types'),'@utils':a('/utils'),'@theme':a('/theme')}},
  server:{port:5190,strictPort:true,proxy:{'/api':{target:'http://127.0.0.1:8000',changeOrigin:true}}}, logLevel:'warn' });
await server.listen(); console.log('vite up');
