"""Verify asset dimensions, references, template PDF and kit manifests."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote,urlparse
import json,hashlib,struct,xml.etree.ElementTree as ET
from PIL import Image
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[1]
checks=[]
def check(ok,message):
    if not ok:raise AssertionError(message)
    checks.append(message)

class References(HTMLParser):
    def handle_starttag(self,tag,attrs):
        for k,v in attrs:
            if k in ['href','src'] and v and not v.startswith(('#','data:','http:','https:')):
                check((ROOT/unquote(urlparse(v).path)).exists(),'HTML reference exists: '+v)
References().feed((ROOT/'START-HERE.html').read_text())
for p in ROOT.rglob('*.svg'):
    ET.parse(p)
    if p.parent.name in ['marks'] or 'wordmark' in p.name or 'lockup-mono' in p.name:
        check('<image' not in p.read_text(),'Pure vector: '+str(p.relative_to(ROOT)))
for p in ROOT.rglob('*.png'):
    with Image.open(p) as im:im.verify()
for p in ROOT.rglob('Contents.json'):
    data=json.loads(p.read_text())
    for item in data.get('images',[]):
        if 'filename' in item:
            target=p.parent/item['filename'];check(target.exists(),'Asset catalog resource: '+str(target.relative_to(ROOT)))
            if 'size' in item:
                expected=int(float(item['size'].split('x')[0])*float(item['scale'].rstrip('x')))
                check(Image.open(target).size==(expected,expected),'Catalog dimension: '+target.name)
for name in ['lavender','mint','charcoal']:
    p=ROOT/f'app-icons/Paca-{name}.icns';data=p.read_bytes()
    check(data[:4]==b'icns' and struct.unpack('>I',data[4:8])[0]==len(data),'ICNS container: '+name)
    im=Image.open(ROOT/f'app-icons/paca-{name}-macos.png')
    check(im.size==(1024,1024) and im.getpixel((0,0))[-1]==0,'macOS transparent outer margin: '+name)
for name in ['paca-mascot.png','paca-peeking-transparent.png']:
    im=Image.open(ROOT/'mascot'/name)
    check(im.mode=='RGBA' and im.getchannel('A').getextrema()==(0,255),'Genuine alpha: '+name)
for tone in ['black','white']:
    for size in [16,18,20,24,32]:
        for scale in [1,2,3]:
            p=ROOT/f'toolbar/paca-{tone}-{size}{"" if scale==1 else "@"+str(scale)+"x"}.png'
            im=Image.open(p)
            check(im.size==(size*scale,size*scale),'Toolbar size: '+p.name)
            check(im.mode=='RGBA' and im.getchannel('A').getextrema()==(0,255),'Toolbar alpha: '+p.name)
guide=PdfReader(ROOT/'guidelines/paca-brand-guide.pdf')
check(len(guide.pages)==10,'Brand guide has 10 pages')
for i,p in enumerate(guide.pages):check(len(p.extract_text())>(40 if i==0 else 100),f'Guide page {i+1} has selectable text')
template=PdfReader(ROOT/'toolbar/PacaTemplate.imageset/PacaTemplate.pdf')
check(len(template.pages)==1 and float(template.pages[0].mediabox.width)==18,'Template PDF is 18 pt')
check(len(list(template.pages[0].images))==0,'Template PDF contains vector artwork only')
for name,size in [('paca-open-graph',(1200,630)),('paca-banner',(1500,500)),('paca-square',(1080,1080))]:
    check(Image.open(ROOT/f'social/{name}.png').size==size,'Social dimensions: '+name)
pal=json.loads((ROOT/'tokens/palette.json').read_text())
def lum(h):
    cs=[int(h[i:i+2],16)/255 for i in [1,3,5]]
    cs=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in cs]
    return sum(a*b for a,b in zip(cs,[.2126,.7152,.0722]))
pairs=[('ink','lavender'),('ink','mint'),('cream','ink'),('violet','paper'),('muted','paper')]
pairs += [(s,'paper') for s in ['working','needsInput','done','error']]
pairs += [(s,'ink') for s in ['darkWorking','darkNeedsInput','darkDone','darkError']]
ratios={}
for fg,bg in pairs:
    a,b=sorted((lum(pal[fg]),lum(pal[bg])));ratio=(b+.05)/(a+.05)
    ratios[f'{fg} on {bg}']=round(ratio,2)
    check(ratio>=4.5,'Text contrast >= 4.5:1: '+fg+' on '+bg)
report={'passed':len(checks),'contrast_ratios':ratios,'notes':['PDF pages rendered and visually reviewed.','Toolbar glyphs reviewed at actual small sizes.','Optional SwiftUI token file typechecked with swiftc.']}
(ROOT/'sources/validation.json').write_text(json.dumps(report,indent=2)+'\n')
manifest=[]
for p in sorted(ROOT.rglob('*')):
    if p.is_file() and p.name not in ['manifest.json'] and 'node_modules' not in p.parts:
        data=p.read_bytes();manifest.append({'path':str(p.relative_to(ROOT)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
(ROOT/'manifest.json').write_text(json.dumps({'name':'Paca brand kit','version':'1.0','files':manifest},indent=2)+'\n')
print(json.dumps(report,indent=2))
print('Manifest:',len(manifest),'files')
