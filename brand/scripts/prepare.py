"""Build outlined wordmarks, native symbols and font subsets. No raster editing."""
from pathlib import Path
import json
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    'lavender': '#B8A2E8', 'mint': '#CDE4D6', 'cream': '#FFF5DE',
    'oat': '#EAD2B2', 'ink': '#28262E', 'outline': '#241F1D',
    'paper': '#FAF8F4', 'violet': '#69508F', 'muted': '#716879',
    'working': '#285FCC', 'needsInput': '#94600E', 'done': '#237345',
    'error': '#B83F37', 'darkWorking': '#8CB4FF',
    'darkNeedsInput': '#F0BE6C', 'darkDone': '#83D8A6', 'darkError': '#FF9C95'
}
(ROOT/'tokens/palette.json').write_text(json.dumps(COLORS, indent=2)+'\n')
font = TTFont(ROOT/'fonts/manrope/Manrope-Variable.ttf')
for weight in [400,600,800]:
    static = instantiateVariableFont(font, {'wght': weight}, inplace=False)
    style={400:'Regular',600:'SemiBold',800:'ExtraBold'}[weight]
    for platform,encoding,language in [(3,1,0x409),(1,0,0)]:
        for name_id,value in [(1,'Manrope'),(2,style),(4,'Manrope '+style),(6,'Manrope-'+style),(16,'Manrope'),(17,style)]:
            static['name'].setName(value,name_id,platform,encoding,language)
    static.save(ROOT/f'fonts/manrope/Manrope-{weight}.ttf')
font.flavor = 'woff2'
font.save(ROOT/'fonts/manrope/Manrope-Variable.woff2')
for weight in ['Regular','Medium']:
    f=TTFont(ROOT/f'fonts/ibm-plex-mono/IBMPlexMono-{weight}.ttf')
    f.flavor='woff2'; f.save(ROOT/f'fonts/ibm-plex-mono/IBMPlexMono-{weight}.woff2')

# Typeface-derived wordmark. Real outlines, no live fonts or raster content.
f=TTFont(ROOT/'fonts/manrope/Manrope-800.ttf')
gs=f.getGlyphSet(); cmap=f.getBestCmap(); hmtx=f['hmtx'].metrics
x=0; elements=[]; bounds=[]
for ch in 'paca':
    name=cmap[ord(ch)]; glyph=gs[name]
    pen=SVGPathPen(gs); glyph.draw(pen)
    bp=BoundsPen(gs); glyph.draw(bp)
    elements.append(f'<path transform="translate({x} 0)" d="{pen.getCommands()}"/>')
    bounds.append((bp.bounds[0]+x,bp.bounds[1],bp.bounds[2]+x,bp.bounds[3]))
    x+=hmtx[name][0]-28
left=min(b[0] for b in bounds); bottom=min(b[1] for b in bounds)
right=max(b[2] for b in bounds); top=max(b[3] for b in bounds)
w=right-left; h=top-bottom
paths=''.join(elements)
meta={'viewBox':[0,0,w,h],'group':f'<g transform="translate({-left} {top}) scale(1 -1)">{paths}</g>'}
(ROOT/'sources/wordmark-paths.json').write_text(json.dumps(meta))
def outline_text(text, weight=600):
    tf=TTFont(ROOT/f'fonts/manrope/Manrope-{weight}.ttf')
    tgs=tf.getGlyphSet(); tc=tf.getBestCmap(); tx=0; nodes=[]; bs=[]
    for ch in text:
        gn=tc[ord(ch)]; gp=SVGPathPen(tgs); tgs[gn].draw(gp)
        bp=BoundsPen(tgs); tgs[gn].draw(bp)
        nodes.append(f'<path transform="translate({tx} 0)" d="{gp.getCommands()}"/>')
        if bp.bounds: bs.append((bp.bounds[0]+tx,bp.bounds[1],bp.bounds[2]+tx,bp.bounds[3]))
        tx+=tf['hmtx'].metrics[gn][0]
    l=min(b[0] for b in bs); b=min(b[1] for b in bs); r=max(b[2] for b in bs); t=max(b[3] for b in bs)
    return {'width':r-l,'height':t-b,'group':f'<g transform="translate({-l} {t}) scale(1 -1)">{"".join(nodes)}</g>'}
copy=['A window into','your herd.','A native macOS client for Herdr.','Keep your agents in view.','Brand kit / 01','Paca','16 px','18 px','24 px','32 px','Light toolbar','Dark menu bar','App icons','Lavender','Mint','Charcoal']
(ROOT/'sources/typeset.json').write_text(json.dumps({s:outline_text(s,600) for s in copy}))
for name,color in [('ink',COLORS['ink']),('cream',COLORS['cream']),('lavender',COLORS['lavender'])]:
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" fill="{color}"><title>Paca</title>{meta["group"]}</svg>'
    (ROOT/f'logos/paca-wordmark-{name}.svg').write_text(svg+'\n')

# Optical symbol designed independently for 16-24 pt use.
# One compound path: transparent counters, not white paint.
silhouette = 'M5.2 8.1 C4.2 6.2 3.6 3.7 4.2 2.1 C4.8 .8 6.7 2 8 5.1 C9.2 3.8 10.8 3.8 12 4.5 C13.4 3.8 15 4 16 5.2 C17.4 2 19.1 .9 19.8 2.2 C20.4 3.7 19.7 6.3 18.8 8.1 C21 9.4 21.5 11.7 20.6 13.4 C21.3 15.7 20.2 17.9 18.4 18.9 L18.7 22.8 Q12 24 5.3 22.8 L5.6 18.9 C3.5 17.7 2.8 15.6 3.5 13.4 C2.6 11.5 3.1 9.4 5.2 8.1 Z'
eyes='M9.6 12.5 A1.2 1.2 0 1 0 7.2 12.5 A1.2 1.2 0 1 0 9.6 12.5 Z M16.8 12.5 A1.2 1.2 0 1 0 14.4 12.5 A1.2 1.2 0 1 0 16.8 12.5 Z'
nose='M10.5 15.7 Q12 15.2 13.5 15.7 Q13 17.1 12 17.5 Q11 17.1 10.5 15.7 Z'
d=silhouette+' '+eyes+' '+nose
(ROOT/'sources/symbol-path.txt').write_text(d+'\n')
for name,color in [('ink',COLORS['ink']),('white','#FFFFFF'),('cream',COLORS['cream'])]:
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="{color}"><title>Paca alpaca symbol</title><path fill-rule="evenodd" d="{d}"/></svg>'
    (ROOT/f'marks/paca-symbol-{name}.svg').write_text(svg+'\n')
(ROOT/'toolbar/paca-template.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><title>Paca</title><path fill-rule="evenodd" d="{d}"/></svg>\n')
print('Created fonts, vector wordmarks, palette and toolbar symbol.')
