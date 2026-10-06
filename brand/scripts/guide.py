"""Create the brand guide and the native vector template PDF."""
from pathlib import Path
import json
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from fontTools.pens.basePen import BasePen
from fontTools.svgLib.path import parse_path

ROOT=Path(__file__).resolve().parents[1]
P=json.loads((ROOT/'tokens/palette.json').read_text())
for name,file in [('Regular','Manrope-400.ttf'),('Semi','Manrope-600.ttf'),('Bold','Manrope-800.ttf')]:
    pdfmetrics.registerFont(TTFont(name,str(ROOT/'fonts/manrope'/file)))
pdfmetrics.registerFont(TTFont('Mono',str(ROOT/'fonts/ibm-plex-mono/IBMPlexMono-Regular.ttf')))
SYMBOL=(ROOT/'sources/symbol-path.txt').read_text()

class CanvasPen(BasePen):
    def __init__(self,p): super().__init__(None); self.p=p
    def _moveTo(self,p): self.p.moveTo(*p)
    def _lineTo(self,p): self.p.lineTo(*p)
    def _curveToOne(self,a,b,c): self.p.curveTo(*a,*b,*c)
    def _closePath(self): self.p.close()
    def _endPath(self): pass

def draw_symbol(c,x,y,size,color):
    c.saveState();c.translate(x,y+size);c.scale(size/24,-size/24)
    p=c.beginPath();parse_path(SYMBOL,CanvasPen(p))
    c.setFillColor(HexColor(color));c.drawPath(p,fill=1,stroke=0,fillMode=0);c.restoreState()

template=ROOT/'toolbar/PacaTemplate.imageset/PacaTemplate.pdf'
c=canvas.Canvas(str(template),pagesize=(18,18),pageCompression=1)
c.setTitle('Paca template symbol');draw_symbol(c,0,0,18,'#000000');c.save()

W,H=960,600
c=canvas.Canvas(str(ROOT/'guidelines/paca-brand-guide.pdf'),pagesize=(W,H),pageCompression=1)
c.setTitle('Paca brand guide');c.setAuthor('Paca');c.setSubject('Identity, mascot, app icons and toolbar assets')
page_no=0
def box(x,y,w,h,color,r=0):
    c.setFillColor(HexColor(P.get(color,color)))
    if r:c.roundRect(x,H-y-h,w,h,r,fill=1,stroke=0)
    else:c.rect(x,H-y-h,w,h,fill=1,stroke=0)
def txt(s,x,y,size=14,font='Regular',color='ink'):
    c.setFillColor(HexColor(P.get(color,color)));c.setFont(font,size)
    c.drawString(x,H-y-size*.82,s)
def para(s,x,y,width,size=14,leading=None,color='ink',font='Regular'):
    leading=leading or size*1.48
    words=s.split();line='';rows=[]
    for w in words:
        proposed=(line+' '+w).strip()
        if pdfmetrics.stringWidth(proposed,font,size)>width and line:rows.append(line);line=w
        else:line=proposed
    if line:rows.append(line)
    for i,line in enumerate(rows):txt(line,x,y+i*leading,size,font,color)
    return y+len(rows)*leading
def img(file,x,y,w,h):
    c.drawImage(str(ROOT/file),x,H-y-h,width=w,height=h,mask='auto',preserveAspectRatio=True,anchor='c')
def start(section,title,sub=None,bg='paper'):
    global page_no
    page_no+=1;box(0,0,W,H,bg)
    txt('PACA / BRAND GUIDE',54,28,10,'Mono','muted')
    txt(f'{page_no:02d} / {section.upper()}',720,28,10,'Mono','muted')
    txt(title,54,73,36,'Bold')
    if sub:para(sub,56,124,850,13,color='muted')
def footer():
    txt('Paca   /   Identity v1.0',54,566,10,'Mono','muted')
    txt('03 OCT 2026',801,566,10,'Mono','muted');c.showPage()

# 01 / Cover
page_no+=1;box(0,0,W,H,'lavender')
img('logos/paca-wordmark-ink.png',58,48,245,100)
txt('A window into',59,237,49,'Semi');txt('your herd.',59,302,60,'Bold')
para('A native macOS client for Herdr.',63,442,440,19)
txt('Brand identity / Version 1.0',63,536,11,'Mono')
img('mascot/paca-peeking-transparent.png',456,96,504,504);c.showPage()

# 02 / Logo
start('Identity','One name. Three useful forms.','Use Paca in prose. Use the supplied lowercase paca artwork in the logo.')
box(54,180,414,195,'#FFFFFF',18);img('logos/paca-lockup-ink.png',77,205,370,130)
box(490,180,416,195,'ink',18);img('logos/paca-lockup-mono-cream.png',512,216,371,105)
txt('Color lockup',69,394,18,'Semi');para('Mascot plus wordmark for websites, welcome screens and brand material. Minimum width: 160 px.',69,426,374,13)
txt('One-color lockup',505,394,18,'Semi');para('Vector symbol plus outlined wordmark for compact and one-color applications. Minimum width: 104 px.',505,426,370,13)
para('Clear space: one-quarter of the symbol height around a lockup. For the wordmark alone, leave half its lowercase x-height.',57,509,850,12,color='muted');footer()

# 03 / Toolbar
start('Small symbol','Made for the menu bar.','The simplified symbol keeps the ears, wool outline and face. The eye and nose counters are transparent.')
box(54,184,852,112,'#FFFFFF',16);box(54,331,852,112,'ink',16)
for i,n in enumerate([16,18,20,24,32]):
    x=95+i*120
    draw_symbol(c,x,H-220-n,n,P['ink']);draw_symbol(c,x,H-368-n,n,'#FFFFFF')
    txt(str(n)+' pt',x-4,269,10,'Mono','muted');txt(str(n)+' pt',x-4,415,10,'Mono','cream')
draw_symbol(c,785,H-202-75,75,P['ink']);draw_symbol(c,785,H-348-75,75,'#FFFFFF')
para('Use 18 pt in the macOS menu bar and 20-24 px in toolbars. Set NSImage.isTemplate to true so macOS controls tint. Keep status counts beside the mark.',56,477,840,14)
txt('Files: toolbar/PacaTemplate.imageset/ and toolbar/paca-template.svg',56,534,11,'Mono','muted');footer()

# 04 / App icon
start('App icons','An alpaca at the window.','The neck crosses the tile edge. The eyes, muzzle and ears remain visible.')
for i,(name,label) in enumerate([('lavender','Primary / lavender'),('mint','Alternate / curious mint'),('charcoal','Alternate / calm charcoal')]):
    x=54+i*294;img(f'app-icons/paca-{name}-macos.png',x,166,264,264)
    txt(label,x+16,438,14,'Semi')
para('Use the supplied .icns or AppIcon asset catalog for macOS. Use the full-square PNG for web avatars. The macOS tile has a transparent outer margin; the mascot meets the inner tile boundary.',56,491,837,14);footer()

# 05 / Palette
start('Color','Soft fields. Clear contrast.','Use ink on the pastel colors. Use cream on dark backgrounds.')
for i,name in enumerate(['lavender','mint','cream','oat','ink','paper']):
    x=54+i*144;box(x,186,132,136,name,14)
    txt(name.capitalize(),x,339,15,'Semi');txt(P[name],x,366,11,'Mono','muted')
box(54,415,414,108,'ink',14);txt('Cream on ink',74,437,19,'Semi','cream');txt('13.77:1',74,479,12,'Mono','cream')
box(490,415,416,108,'lavender',14);txt('Ink on lavender',510,437,19,'Semi');txt('6.66:1',510,479,12,'Mono')
txt('Violet #69508F on paper: 6.30:1. Use violet for links and actions on light backgrounds.',56,539,11,'Regular','muted');footer()

# 06 / Typography
start('Typography','Manrope, with a native UI.','A rounded sans for the brand. System fonts for the macOS app.')
txt('A window into',54,182,52,'Semi');txt('your herd.',54,247,62,'Bold')
para('Paca brings your Herdr workspaces, agents and terminals into a native macOS app.',57,349,520,21,leading=31)
txt('WORKING / 3 AGENTS',57,465,15,'Mono','violet')
box(660,178,246,350,'#FFFFFF',16)
txt('Brand scale',684,202,19,'Semi')
for i,(a,b) in enumerate([('Display','56-72 px / 600'),('Heading','32-40 px / 600'),('Body','16-18 px / 400'),('Technical label','12-14 px / Mono')]):
    txt(a,684,246+i*58,13,'Semi');txt(b,684,269+i*58,11,'Mono','muted')
para('Fonts and OFL license files are included. Native controls keep SF Pro; terminal text keeps its configured monospace font.',56,518,557,12,color='muted');footer()

# 07 / Mascot
start('Mascot','Keep the peeking crop deliberate.','Align the cut neck with a window edge. Use the complete mascot when it stands alone.')
box(54,182,405,305,'cream',18);img('mascot/paca-mascot.png',107,188,292,292)
box(492,182,414,305,'mint');img('mascot/paca-peeking-transparent.png',601,182,305,305)
txt('Complete portrait',68,505,18,'Semi');txt('Window composition',508,505,18,'Semi')
txt('No crop. Keep clear space around the silhouette.',69,535,11,'Regular','muted')
txt('Neck meets bottom and right edges. Ears stay visible.',508,535,11,'Regular','muted');footer()

# 08 / Voice
start('Voice and interface','Say what the agent needs.','Use plain language. Keep the mascot playful and the interface precise.')
box(54,183,413,346,'#FFFFFF',16)
entries=[('ATTENTION','2 agents need input.'),('EMPTY STATE','No agents in this workspace.'),('DISCONNECTED','Herdr is offline. Start Herdr to reconnect.'),('APPROVAL','This agent needs approval. Open its terminal to respond.')]
y=204
for label,body in entries:
    txt(label,76,y,10,'Mono','muted');para(body,76,y+24,368,15);y+=77
txt('Status is separate from brand color.',500,191,20,'Semi')
for i,(label,color) in enumerate([('Working','working'),('Needs input','needsInput'),('Done','done'),('Error','error')]):
    y=240+i*42;box(501,y+3,12,12,color,6);txt(label,529,y,15,'Semi')
para('Pair color with a label and a distinct shape. The optional token files include separate light and dark values.',501,424,389,14)
para('Copy examples are guidance. Check shipped capabilities before using them in product marketing.',501,498,389,11,color='muted');footer()

# 09 / Social
start('Applications','Ready for a first introduction.','Use the prepared layouts for previews, project pages and social accounts.')
img('social/paca-open-graph.png',54,189,554,291)
img('social/paca-banner.png',640,189,266,89)
img('social/paca-square.png',678,312,190,190)
txt('Open Graph / 1200 x 630',56,502,12,'Mono','muted')
txt('Banner / 1500 x 500',640,288,10,'Mono','muted')
txt('Square / 1080 x 1080',678,519,10,'Mono','muted');footer()

# 10 / Handoff
start('Handoff','Everything lives in brand/.','Keep the source artwork. Choose the smallest asset that fits the job.')
rows=[('logos/','Wordmarks, color lockups and one-color lockups'),('marks/ + toolbar/','Vector glyph, template PDF and raster toolbar sizes'),('app-icons/','Three .icns files, iconsets and an Xcode catalog'),('web/ + social/','Favicons, web manifest, avatars and social templates'),('fonts/ + tokens/','Font files, licenses, CSS, JSON and SwiftUI tokens'),('mascot/ + originals/','Transparent artwork and preserved generated originals'),('scripts/ + sources/','Rebuild scripts, provenance and generation prompts')]
for i,(a,b) in enumerate(rows):
    y=186+i*40
    if i%2==0:box(54,y-5,852,37,'#FFFFFF',6)
    txt(a,67,y+4,12,'Mono');txt(b,291,y+3,13)
para('The symbol and wordmarks are vector. Color mascot layouts embed 1254 px raster artwork. The kit is saved separately; it does not change the application theme or bundle configuration.',58,488,837,13)
txt('Font sources and licenses: sources/provenance.json and fonts/*/OFL.txt',58,542,10,'Mono','muted');footer()
c.save()
print('Created 10-page guide and 18 pt vector template PDF.')
