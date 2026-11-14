// Real Chromium geometry regression for Pesto form actions. Local installed browser only, no download/Windows/AD.
// PESTO_PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs PESTO_CHROMIUM_PATH=/usr/bin/google-chrome node tools/tests/web-layout-check.mjs
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, extname, isAbsolute, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
// « Un poste » targets this PC by default: searching another computer starts with that explicit choice.
const pickRemote = async (page) => { const remote = page.locator('[data-form="target"] input[value="remote"]'); if (await remote.count()) await remote.check(); };
const web=resolve(dirname(fileURLToPath(import.meta.url)),"../../web");
const moduleName=process.env.PESTO_PLAYWRIGHT_MODULE||"playwright";
const {chromium}=await import(isAbsolute(moduleName)?pathToFileURL(moduleName).href:moduleName);
const executablePath=process.env.PESTO_CHROMIUM_PATH||["/usr/bin/google-chrome","/usr/bin/chromium"].find(existsSync);
assert(executablePath&&existsSync(executablePath),"Installed Chromium required; no automatic download.");
const server=createServer(async(req,res)=>{try{const file=resolve(web,"."+(new URL(req.url,"http://localhost").pathname==="/"?"/index.html":new URL(req.url,"http://localhost").pathname));assert(file.startsWith(web+sep));const body=await readFile(file);res.writeHead(200,{"Content-Type":({".js":"text/javascript",".css":"text/css",".html":"text/html"})[extname(file)]||"application/octet-stream"});res.end(body);}catch{res.writeHead(404);res.end();}});
await new Promise(done=>server.listen(0,"127.0.0.1",done));
let browser,checks=0,failures=0;
try{
 browser=await chromium.launch({headless:true,executablePath});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 await page.addInitScript(()=>localStorage.setItem("pesto.prefs.v1",JSON.stringify({theme:"light",motion:"reduced"})));
 await page.goto(`http://127.0.0.1:${server.address().port}`);
 for(const width of [1440,1024]){
  await page.setViewportSize({width,height:1000});
  for(const [id,form] of [["ajouter","join"],["noms","preview"],["plusieurspostes","paste"],["unposte","rename"]]){
   checks++;
   try{
    await page.locator(`.nav-item[data-id="${id}"]`).click();
    await page.waitForFunction(id=>document.documentElement.dataset.ready===id,id);
    assert.equal(await page.locator("main .error-card").count(),0);
    if(id==="unposte"){
     await pickRemote(page);const search=page.locator("form[data-form=search] [name=query]");await search.fill("P111301PAINF001");await search.press("Enter");await page.locator("[data-pick=P111301PAINF001]").click();
    }
    const button=page.locator(`form[data-form="${form}"] > .row-actions > button[type=submit]`);
    await button.waitFor({state:"visible"});
    const geometry=await button.evaluate(el=>{
     const b=el.getBoundingClientRect(),row=el.parentElement.getBoundingClientRect(),form=el.closest("form").getBoundingClientRect();
     const walker=document.createTreeWalker(el,NodeFilter.SHOW_TEXT);const text=[];
     while(walker.nextNode()){if(!walker.currentNode.textContent.trim())continue;const range=document.createRange();range.selectNodeContents(walker.currentNode);for(const r of range.getClientRects())text.push({left:r.left,right:r.right,top:r.top,bottom:r.bottom});}
     return {button:{left:b.left,right:b.right,top:b.top,bottom:b.bottom,width:b.width},rowWidth:row.width,formWidth:form.width,clientWidth:el.clientWidth,scrollWidth:el.scrollWidth,text};
    });
    assert(geometry.rowWidth>=geometry.formWidth-1,"Action row is squeezed into one grid column: "+JSON.stringify(geometry));
    assert(geometry.scrollWidth<=geometry.clientWidth+1,"Button content overflows: "+JSON.stringify(geometry));
    assert(geometry.text.length>0,"No visible button label");
    for(const r of geometry.text)assert(r.left>=geometry.button.left-1&&r.right<=geometry.button.right+1&&r.top>=geometry.button.top-1&&r.bottom<=geometry.button.bottom+1,"Label is clipped: "+JSON.stringify(geometry));
    assert(Math.max(...geometry.text.map(r=>r.top))-Math.min(...geometry.text.map(r=>r.top))<2,"Label wraps across lines");
    console.log(`ok ${width}px ${id}: button ${geometry.button.width.toFixed(1)}px, row ${geometry.rowWidth.toFixed(1)}px, label contained`);
   }catch(e){failures++;console.error(`FAIL ${width}px ${id}: ${e.message}`);}
  }
 }
}finally{await browser?.close();server.close();}
console.log(`${checks-failures}/${checks} checks passed`);if(failures)process.exitCode=1;
