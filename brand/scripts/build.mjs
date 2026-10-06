/** Mechanical exports and original vector layouts. Does not redraw raster artwork. */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
const require=createRequire(import.meta.url);
const sharp=require(process.env.PACA_SHARP_PATH || 'sharp');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=(p)=>fs.readFile(path.join(root,p));
const json=async p=>JSON.parse(await read(p));
const write=async(p,data)=>{await fs.mkdir(path.dirname(path.join(root,p)),{recursive:true});await fs.writeFile(path.join(root,p),data);};
const palette=await json('tokens/palette.json');
const wm=await json('sources/wordmark-paths.json');
const copy=await json('sources/typeset.json');
const symbolD=(await read('sources/symbol-path.txt')).toString().trim();
const pngData=async p=>'data:image/png;base64,'+(await read(p)).toString('base64');
const mascot=await pngData('mascot/paca-mascot.png');
const peek=await pngData('mascot/paca-peeking-transparent.png');
const image=(href,x,y,w,h)=>`<image href="${href}" x="${x}" y="${y}" width="${w}" height="${h}"/>`;
const svg=(w,h,b)=>`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${b}</svg>`;
const rect=(x,y,w,h,fill,r=0)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}"/>`;
const word=(x,y,w,color)=>`<g fill="${color}" transform="translate(${x} ${y}) scale(${w/wm.viewBox[2]})">${wm.group}</g>`;
const glyph=(x,y,size,color)=>`<path fill="${color}" fill-rule="evenodd" transform="translate(${x} ${y}) scale(${size/24})" d="${symbolD}"/>`;
const text=(s,x,y,h,color)=>{let t=copy[s];return `<g fill="${color}" transform="translate(${x} ${y}) scale(${h/t.height})">${t.group}</g>`;};
const render=async(p,s,w)=>{await write(p+'.svg',s);await sharp(Buffer.from(s)).resize({width:w}).png().toFile(path.join(root,p+'.png'));};

// Font-independent outlined wordmarks and transparent logo lockups.
for(const color of ['ink','cream','lavender']) await sharp(await read(`logos/paca-wordmark-${color}.svg`)).resize(1600).png().toFile(path.join(root,`logos/paca-wordmark-${color}.png`));
for(const tone of ['ink','cream']){
 const c=palette[tone];
 await render(`logos/paca-lockup-${tone}`,svg(600,190,image(mascot,0,0,190,190)+word(213,56,350,c)),1800);
 await render(`logos/paca-stacked-${tone}`,svg(360,400,image(mascot,40,0,280,280)+word(62,294,236,c)),1080);
 await render(`logos/paca-lockup-mono-${tone}`,svg(570,160,glyph(10,6,142,c)+word(186,45,350,c)),1710);
}
// True vector toolbar exports, with separate black and white PNGs.
for(const [tone,color] of [['black','#000000'],['white','#FFFFFF']]){
 for(const size of [16,18,20,24,32]){
  for(const scale of [1,2,3]){
   const s=svg(size,size,glyph(0,0,size,color));
   await sharp(Buffer.from(s)).resize(size*scale,size*scale).png().toFile(path.join(root,`toolbar/paca-${tone}-${size}${scale===1?'':`@${scale}x`}.png`));
  }
 }
}
const imageset='toolbar/PacaTemplate.imageset';
await write(`${imageset}/Contents.json`,JSON.stringify({images:[{filename:'PacaTemplate.pdf',idiom:'universal'}],info:{author:'xcode',version:1},properties:{'preserves-vector-representation':true,'template-rendering-intent':'template'}},null,2));

// Desktop app icons. The colored window is inset on a transparent macOS canvas.
const sizes=[16,32,64,128,256,512,1024];
for(const variant of ['lavender','mint','charcoal']){
 const href=await pngData(`originals/paca-peek-${variant}.png`);
 for(const n of sizes) await sharp(await read(`originals/paca-peek-${variant}.png`)).resize(n,n).png().toFile(path.join(root,`app-icons/paca-${variant}-${n}.png`));
 const mac=svg(1024,1024,`<defs><clipPath id="tile">${rect(64,64,896,896,'white',198)}</clipPath></defs><g clip-path="url(#tile)">${image(href,64,64,896,896)}</g>`);
 await render(`app-icons/paca-${variant}-macos`,mac,1024);
 const iconset=`app-icons/Paca-${variant}.iconset`;
 await fs.mkdir(path.join(root,iconset),{recursive:true});
 for(const n of [16,32,128,256,512]) for(const scale of [1,2]){
  await sharp(Buffer.from(mac)).resize(n*scale,n*scale).png().toFile(path.join(root,`${iconset}/icon_${n}x${n}${scale===2?'@2x':''}.png`));
 }
 execFileSync('/usr/bin/iconutil',['-c','icns',path.join(root,iconset),'-o',path.join(root,`app-icons/Paca-${variant}.icns`)]);
}
const xc='app-icons/PacaAssets.xcassets';
await write(`${xc}/Contents.json`,JSON.stringify({info:{author:'xcode',version:1}},null,2));
const appImages=[];
for(const n of [16,32,128,256,512]) for(const scale of [1,2]){
 const filename=`icon_${n}x${n}${scale===2?'@2x':''}.png`;
 await write(`${xc}/AppIcon.appiconset/${filename}`,await read(`app-icons/Paca-lavender.iconset/${filename}`));
 appImages.push({filename,idiom:'mac',scale:`${scale}x`,size:`${n}x${n}`});
}
await write(`${xc}/AppIcon.appiconset/Contents.json`,JSON.stringify({images:appImages,info:{author:'xcode',version:1}},null,2));
// Favicons use the optical symbol, not the detailed portrait.
const favicon=svg(64,64,rect(0,0,64,64,palette.lavender,14)+glyph(12,8,40,palette.ink));
await write('web/favicon.svg',favicon);
const frames=[];
for(const n of [16,32,48]){
 const data=await sharp(Buffer.from(favicon)).resize(n,n).png().toBuffer();
 await write(`web/favicon-${n}.png`,data);frames.push({n,data});
}
const header=Buffer.alloc(6+frames.length*16);header.writeUInt16LE(1,2);header.writeUInt16LE(frames.length,4);
let offset=header.length;
for(let i=0;i<frames.length;i++){
 const {n,data}=frames[i],p=6+i*16;header[p]=n;header[p+1]=n;header.writeUInt16LE(1,p+4);header.writeUInt16LE(32,p+6);header.writeUInt32LE(data.length,p+8);header.writeUInt32LE(offset,p+12);offset+=data.length;
}
await write('web/favicon.ico',Buffer.concat([header,...frames.map(f=>f.data)]));
for(const [file,n] of [['apple-touch-icon.png',180],['paca-192.png',192],['paca-512.png',512]])await write('web/'+file,await sharp(await read('originals/paca-peek-lavender.png')).resize(n,n).png().toBuffer());
await write('web/site.webmanifest',JSON.stringify({name:'Paca',short_name:'Paca',icons:[{src:'paca-192.png',sizes:'192x192',type:'image/png',purpose:'any'},{src:'paca-512.png',sizes:'512x512',type:'image/png',purpose:'any'}],theme_color:palette.ink,background_color:palette.paper,display:'standalone'},null,2));

// Editable vector layout files embed the original PNG character and outlined type.
await render('social/paca-open-graph',svg(1200,630,
 rect(0,0,1200,630,palette.lavender)+word(72,60,180,palette.ink)+
 text('A window into',72,238,55,palette.ink)+text('your herd.',72,315,64,palette.ink)+
 text('A native macOS client for Herdr.',74,514,18,palette.ink)+image(peek,570,0,630,630)),1200);
await render('social/paca-banner',svg(1500,500,
 rect(0,0,1500,500,palette.ink)+word(80,92,270,palette.cream)+
 text('Keep your agents in view.',83,270,35,palette.cream)+
 text('A native macOS client for Herdr.',85,397,17,palette.mint)+image(peek,1000,0,500,500)),1500);
await render('social/paca-square',svg(1080,1080,
 rect(0,0,1080,1080,palette.mint)+word(70,65,275,palette.ink)+
 text('A window into',73,224,39,palette.ink)+text('your herd.',73,281,47,palette.ink)+image(peek,320,320,760,760)),1080);
for(const variant of ['lavender','mint','charcoal'])await write(`social/paca-avatar-${variant}.png`,await sharp(await read(`originals/paca-peek-${variant}.png`)).resize(512,512).png().toBuffer());

// Small glyphs are shown at actual pixels, not only as enlarged illustrations.
let preview=rect(0,0,1280,760,palette.paper);
preview+=text('Paca',56,45,46,palette.ink)+text('Light toolbar',60,133,18,palette.muted);
preview+=rect(48,180,1184,108,'#FFFFFF',16);
for(const [i,n] of [16,18,24,32].entries()){
 const x=92+i*130;preview+=glyph(x,220,n,palette.ink)+text(`${n} px`,x,310,13,palette.muted);
}
preview+=glyph(1010,188,92,palette.ink);
preview+=text('Dark menu bar',60,390,18,palette.muted)+rect(48,435,1184,108,palette.ink,16);
for(const [i,n] of [16,18,24,32].entries()){
 const x=92+i*130;preview+=glyph(x,475,n,'#FFFFFF')+text(`${n} px`,x,565,13,palette.muted);
}
preview+=glyph(1010,443,92,'#FFFFFF');
await render('previews/toolbar-preview',svg(1280,760,preview),1280);
let board=rect(0,0,1600,980,palette.paper)+word(65,55,275,palette.ink)+text('Brand kit / 01',1260,82,18,palette.muted);
board+=rect(64,190,720,720,palette.lavender,42)+image(await pngData('originals/paca-peek-lavender.png'),64,190,720,720);
board+=rect(824,190,710,270,palette.ink,28)+word(885,265,310,palette.cream)+glyph(1340,256,128,palette.cream);
board+=image(await pngData('originals/paca-peek-mint.png'),824,500,330,330)+image(await pngData('originals/paca-peek-charcoal.png'),1204,500,330,330);
for(const [i,c] of ['lavender','mint','cream','oat','ink'].entries())board+=rect(824+i*142,870,142,40,palette[c]);
await render('previews/brand-overview',svg(1600,980,board),1600);
console.log('Exported logo layouts, toolbar glyphs, three macOS icon bundles, web icons, social assets and previews.');
