#!/usr/bin/env python3
"""Generate a colour-coded wiring/breadboard diagram (SVG) for hardware_better.
Not a Fritzing .fzz (that must be assembled in Fritzing) — a readable connection
diagram you can wire from. Run: python breadboard_diagram.py  ->  breadboard_diagram.svg
"""
import os

W, H = 1500, 1100
C = {  # net colours
    "5V": "#d8332a", "3V3": "#e8920c", "GND": "#333333",
    "panel": "#2b6cb0", "sel": "#b21fb2", "pot": "#2e8b57",
    "sw": "#8a5a2b", "probe": "#7a3fb0", "uart": "#666666",
}
el = []
def rect(x, y, w, h, fill="#fff", stroke="#222", sw=1.5, rx=6):
    el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')
def txt(x, y, s, size=12, anchor="start", fill="#111", weight="normal"):
    s = str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    el.append(f'<text x="{x}" y="{y}" font-family="Helvetica,Arial" font-size="{size}" '
              f'text-anchor="{anchor}" fill="{fill}" font-weight="{weight}">{s}</text>')
def dot(x, y, fill="#222"):
    el.append(f'<circle cx="{x}" cy="{y}" r="3.2" fill="{fill}"/>')
def wire(p, color):  # p = list of (x,y) points; elbow polyline
    pts = " ".join(f"{x},{y}" for x, y in p)
    el.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2.4" '
              f'stroke-linecap="round" stroke-linejoin="round"/>')

el.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="Helvetica,Arial">')
rect(0, 0, W, H, fill="#fbfbf7", stroke="#fbfbf7", rx=0)
txt(24, 34, "EE2 FDTD — hardware_better breadboard wiring (DG413 two-panel)", 18, weight="bold")

# ---- power rails ----
def rail(y, name, color):
    el.append(f'<rect x="40" y="{y}" width="{W-80}" height="10" fill="{color}"/>')
    txt(44, y-4, name, 12, fill=color, weight="bold")
rail(58, "+5 V", C["5V"])
rail(86, "CTRL_3V3 (3.3 V, from MCP6002)", C["3V3"])
rail(H-40, "GND", C["GND"])
def tap(x, y_from, rail_y, color):  # vertical tap to a rail
    wire([(x, y_from), (x, rail_y)], color)
    dot(x, rail_y, color)

# ---- ESP32 ----
ex, ey, ew, eh = 70, 150, 210, 760
rect(ex, ey, ew, eh, fill="#eef3ff")
txt(ex+ew/2, ey+24, "ESP32-WROOM-32", 14, "middle", weight="bold")
# power taps on left edge
txt(ex+10, ey+52, "5V", 11, fill=C["5V"]); dot(ex, ey+48, C["5V"]); tap(ex-20, ey+48, 68, C["5V"]); wire([(ex,ey+48),(ex-20,ey+48)],C["5V"])
txt(ex+10, ey+74, "GND", 11, fill=C["GND"]); dot(ex, ey+70, C["GND"]); wire([(ex,ey+70),(ex-30,ey+70),(ex-30,H-40)],C["GND"]); dot(ex-30,H-40,C["GND"])

# ESP32 GPIO pins on the right edge (top -> bottom), grouped
esp = [
    ("18","X+ drive","panel"), ("32","X+ sense","panel"),
    ("25","Y+ drive","panel"), ("35","Y+ sense","panel"),
    ("23","X- bus","panel"),   ("22","Y- bus","panel"),
    ("19","MUX_SEL","sel"),
    ("34","Probe","probe"),
    ("39","Amp pot","pot"), ("33","Cond pot","pot"), ("4","Field pot","pot"),
    ("21","Mode sw","sw"), ("26","2D/3D sw","sw"), ("27","Wall sw","sw"), ("14","Clear","sw"),
    ("17","UART TX","uart"), ("16","UART RX","uart"),
]
p0 = ey+70; step = (eh-100)/(len(esp)-1)
epin = {}
for i,(g,lbl,net) in enumerate(esp):
    y = p0 + i*step
    dot(ex+ew, y, C[net]); txt(ex+ew-8, y+4, f"{g} {lbl}", 10.5, "end")
    epin[g] = (ex+ew, y)

# ---- helper to place a component box with left/right pins ----
def box(x, y, w, h, title, fill="#fff"):
    rect(x, y, w, h, fill=fill); txt(x+w/2, y+18, title, 12.5, "middle", weight="bold")

# ---- DG413 ----
dx, dy, dw, dh = 470, 250, 170, 230
box(dx, dy, dw, dh, "DG413 mux (5V)", "#fff3f0")
# left pins: COM_a, COM_b, SEL, V+, GND
dcom_a=(dx, dy+60); dcom_b=(dx, dy+110); dsel=(dx, dy+160); dvp=(dx, dy+195); dgnd=(dx, dy+220)
for (px,py),t,col in [(dcom_a,"COMa","panel"),(dcom_b,"COMb","panel"),(dsel,"SEL","sel"),(dvp,"V+","5V"),(dgnd,"GND","GND")]:
    dot(px,py,C[col]); txt(px+8,py+4,t,10)
# right pins: NCa->P1X+, NOa->P2X+, NCb->P1Y+, NOb->P2Y+
dnc_a=(dx+dw, dy+45); dno_a=(dx+dw, dy+90); dnc_b=(dx+dw, dy+150); dno_b=(dx+dw, dy+195)
for (px,py),t in [(dnc_a,"NCa"),(dno_a,"NOa"),(dnc_b,"NCb"),(dno_b,"NOb")]:
    dot(px,py,C["panel"]); txt(px-8,py+4,t,10,"end")
# V+/GND taps
wire([dvp,(dx-25,dvp[1]),(dx-25,68)],C["5V"]); dot(dx-25,68,C["5V"])
wire([dgnd,(dx-40,dgnd[1]),(dx-40,H-40)],C["GND"]); dot(dx-40,H-40,C["GND"])

# ---- MCP6002 ----
mx,my,mw,mh = 470, 560, 170, 180
box(mx,my,mw,mh,"MCP6002 (5V)","#f0f7f0")
mprobe=(mx, my+50); m34=(mx+mw, my+50); m3v3=(mx+mw, my+110); mref=(mx, my+110)
dot(mprobe[0],mprobe[1],C["probe"]); txt(mprobe[0]+8,mprobe[1]+4,"A: probe in",9.5)
dot(m34[0],m34[1],C["probe"]); txt(m34[0]-8,m34[1]+4,"A: ->18k/33k",9.5,"end")
dot(mref[0],mref[1],C["3V3"]); txt(mref[0]+8,mref[1]+4,"B: 1.7k/3.3k",9.5)
dot(m3v3[0],m3v3[1],C["3V3"]); txt(m3v3[0]-8,m3v3[1]+4,"B: CTRL_3V3",9.5,"end")
# 3V3 out -> rail; V+ -> 5V; GND
wire([m3v3,(mx+mw+25,m3v3[1]),(mx+mw+25,96),(60,96)],C["3V3"]); dot(60,96,C["3V3"])
tap(mx+60,my+mh,H-40,C["GND"]); wire([(mx+60,my+mh-1),(mx+60,my+mh)],C["GND"])
txt(mx+8,my+mh-6,"V+ =5V  V- =GND",9,fill="#555")

# ---- Panels ----
def panel(x,y,name,throwsX,throwsY):
    box(x,y,150,96,name,"#eef6ff")
    xp=(x,y+34); yp=(x,y+56); xm=(x,y+78)
    dot(*xp,C["panel"]); txt(xp[0]+8,xp[1]+4,"X+ (pin4)",9.5)
    dot(*yp,C["panel"]); txt(yp[0]+8,yp[1]+4,"Y+ (pin3)",9.5)
    dot(*xm,C["panel"]); txt(xm[0]+8,xm[1]+4,"X-/Y- (pin2/1)",9.5)
    return xp,yp,xm
p1xp,p1yp,p1xm = panel(720,190,"Panel 1 (Mode 1)",dnc_a,dnc_b)
p2xp,p2yp,p2xm = panel(720,330,"Panel 2 (Mode 2)",dno_a,dno_b)

# ---- sheet/probe ----
box(720,470,200,120,"Mode-1 sheet + probe","#fdf0f6")
txt(730,512,"centre -> +5V , edges -> GND",9.5)
sprobe=(720,548); dot(*sprobe,C["probe"]); txt(sprobe[0]+8,sprobe[1]+4,"probe -> MCP6002 A",9.5)

# ---- pots ----
def pot(x,y,name,gpio):
    box(x,y,160,64,name,"#eef7f0")
    top=(x,y+24); wip=(x,y+42); bot=(x+160,y+42)
    dot(*top,C["3V3"]); txt(top[0]+8,top[1]+4,"top 3V3",9)
    dot(*wip,C["pot"]); txt(wip[0]+8,wip[1]+4,f"wiper -> {gpio}",9)
    dot(*bot,C["GND"]); txt(bot[0]-8,bot[1]+4,"GND",9,"end")
    return top,wip,bot
amp=pot(1090,150,"Amplitude pot","39")
cond=pot(1090,230,"Conductivity pot","33")
field=pot(1090,310,"Field-type pot","4")

# ---- switches ----
def sw(x,y,name,gpio):
    box(x,y,160,46,name,"#f7f2ec")
    a=(x,y+30); b=(x+160,y+30)
    dot(*a,C["sw"]); txt(a[0]+8,a[1]+4,f"{gpio}",9)
    dot(*b,C["GND"]); txt(b[0]-8,b[1]+4,"GND",9,"end")
    return a
smode=sw(1090,430,"Mode 1/2 switch","21")
sdisp=sw(1090,486,"2D/3D switch","26")
swall=sw(1090,542,"Wall/Source switch","27")
sclear=sw(1090,598,"Clear button","14")

# ---- PYNQ ----
box(1090,690,200,90,"PYNQ-Z1 (UART)","#eee")
pd0=(1090,724); pd1=(1090,752)
dot(*pd0,C["uart"]); txt(pd0[0]+8,pd0[1]+4,"D0 (RX) <- TX",9.5)
dot(*pd1,C["uart"]); txt(pd1[0]+8,pd1[1]+4,"D1 (TX) -> RX",9.5)

# ---- WIRES from ESP32 ----
def route(a,b,color,midx=None):
    midx = midx if midx else (a[0]+b[0])/2
    wire([a,(midx,a[1]),(midx,b[1]),b],color)
# panel COMs
route(epin["18"],dcom_a,C["panel"],360); route(epin["32"],dcom_a,C["panel"],375)
route(epin["25"],dcom_b,C["panel"],360); route(epin["35"],dcom_b,C["panel"],375)
route(epin["19"],dsel,C["sel"],400)
# X-/Y- direct to both panels (over the top)
wire([epin["23"],(330,epin["23"][1]),(330,150),(700,150),(700,p1xm[1]),p1xm],C["panel"])
wire([(700,p1xm[1]),(700,p2xm[1]),p2xm],C["panel"])
wire([epin["22"],(345,epin["22"][1]),(345,165),(690,165)],C["panel"]); wire([(690,165),(690,p2xm[1]+6)],C["panel"])
# DG413 throws -> panels
route(dnc_a,p1xp,C["panel"],685); route(dno_a,p2xp,C["panel"],690)
route(dnc_b,p1yp,C["panel"],700); route(dno_b,p2yp,C["panel"],695)
# probe
route(epin["34"],m34,C["probe"],440); route(sprobe,mprobe,C["probe"],690)
# pots
route(epin["39"],amp[1],C["pot"],1040); route(epin["33"],cond[1],C["pot"],1050); route(epin["4"],field[1],C["pot"],1060)
for t in (amp[0],cond[0],field[0]): wire([t,(t[0]-12,t[1]),(t[0]-12,96)],C["3V3"]);
for b in (amp[2],cond[2],field[2]): wire([b,(b[0]+14,b[1]),(b[0]+14,H-40)],C["GND"]); dot(b[0]+14,H-40,C["GND"])
# switches
route(epin["21"],smode,C["sw"],1035); route(epin["26"],sdisp,C["sw"],1045)
route(epin["27"],swall,C["sw"],1055); route(epin["14"],sclear,C["sw"],1065)
for a in (smode,sdisp,swall,sclear): wire([(a[0]+160,a[1]),(a[0]+182,a[1]),(a[0]+182,H-40)],C["GND"]); dot(a[0]+182,H-40,C["GND"])
# UART
route(epin["17"],pd0,C["uart"],1040); route(epin["16"],pd1,C["uart"],1050)

# ---- legend ----
lx,ly=24,H-150
rect(lx,ly,280,118,fill="#fff")
txt(lx+10,ly+18,"Wire colours",11,weight="bold")
for i,(k,lab) in enumerate([("5V","+5 V"),("3V3","CTRL_3V3"),("GND","GND"),("panel","panel X/Y"),
                            ("sel","MUX_SEL"),("pot","pot wiper"),("sw","switch"),("probe","probe"),("uart","UART")]):
    yy=ly+34+i*9 if i<5 else ly+34+(i-5)*9; xx=lx+10 if i<5 else lx+150
    el.append(f'<line x1="{xx}" y1="{yy-3}" x2="{xx+22}" y2="{yy-3}" stroke="{C[k]}" stroke-width="3"/>')
    txt(xx+28,yy,lab,9.5)

el.append("</svg>")
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "breadboard_diagram.svg")
open(out,"w").write("\n".join(el))
print("wrote", out)
