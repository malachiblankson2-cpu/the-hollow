const { chromium } = require('playwright');
const jobs = [["icon",512,512],["title",1920,1080],["keys",1920,1080],["behind",1920,1080],["gate",1920,1080],["jumpscare",1920,1080],["flashlight",512,512],["stamina",512,512],["revive",512,512],["freeze",512,512]];
(async () => {
  const b = await chromium.launch();
  for (const [s,w,h] of jobs) {
    const p = await b.newPage({ viewport: { width: w, height: h } });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.goto(`file://${process.cwd()}/scenes.html?s=${s}&w=${w}&h=${h}`);
    await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(1500);
    await p.screenshot({ path: `${s}.png` });
    console.log(s, errs.length ? errs : 'ok');
  }
  await b.close();
})();
