#!/usr/bin/env python3
"""Single-board / single-panel wiring diagram (SVG) for hardware_onepanel.
Not a Fritzing .fzz (assemble that in Fritzing) — a readable connection diagram.
Run: python breadboard_diagram.py  ->  breadboard_diagram.svg
One ESP32, one directly-wired panel (no DG413), 7 pots + 4 switches, one UART to the PYNQ.
"""
import os
W,H=1560,1180
C={"5V":"#d8332a","3V3":"#e8920c","GND":"#333333","panel":"#2b6cb0",
   "pot":"#2e8b57","sw":"#8a5a2b","probe":"#7a3fb0","uart":"#666666"}
el=[]
def rect(x,y,w,h,fill="#fff",stroke="#222",sw=1.5,rx=6):
    el.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')
def txt(x,y,s,size=12,anchor="start",fill="#111",weight="normal"):
    s=str(s).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    el.append(f'<text x="{x}" y="{y}" font-family="Helvetica,Arial" font-size="{size}" text-anchor="{anchor}" fill="{fill}" font-weight="{weight}">{s}</text>')
def dot(x,y,fill="#222"): el.append(f'<circle cx="{x}" cy="{y}" r="3.2" fill="{fill}"/>')
def wire(p,color): el.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in p)}" fill="none" stroke="{color}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')
def route(a,b,color,midx=None):
    midx=midx if midx else (a[0]+b[0])/2
    wire([a,(midx,a[1]),(midx,b[1]),b],color)

el.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="Helvetica,Arial">')
rect(0,0,W,H,fill="#fbfbf7",stroke="#fbfbf7",rx=0)
txt(24,34,"EE2 FDTD — hardware_onepanel: one ESP32, one panel, 7 pots (no mux, no 2nd board)",17,weight="bold")
def rail(y,name,color): el.append(f'<rect x="40" y="{y}" width="{W-80}" height="10" fill="{color}"/>'); txt(44,y-4,name,12,fill=color,weight="bold")
rail(58,"+5 V",C["5V"]); rail(86,"CTRL_3V3 (3.3 V, from MCP6002)",C["3V3"]); rail(H-40,"GND",C["GND"])
def box(x,y,w,h,title,fill="#fff"): rect(x,y,w,h,fill=fill); txt(x+w/2,y+18,title,12.5,"middle",weight="bold")
def gnd_tap(x,yfrom): wire([(x,yfrom),(x,H-40)],C["GND"]); dot(x,H-40,C["GND"])
def v5_tap(x,yto): wire([(x,68),(x,yto)],C["5V"]); dot(x,68,C["5V"])

# ESP32 (20 pins)
ex,ey,ew=70,170,200; pins=[
 ("18","X+ drive","panel"),("32","X+ sense","panel"),("25","Y+ drive","panel"),("35","Y+ sense","panel"),
 ("23","X-","panel"),("22","Y-","panel"),("34","Probe","probe"),
 ("13","Amp pot","pot"),("33","Cond pot","pot"),("4","Field pot","pot"),
 ("27","Yaw pot","pot"),("14","Pitch pot","pot"),("26","Zoom pot","pot"),("36","Zscale pot","pot"),
 ("21","Mode sw","sw"),("19","2D/3D sw","sw"),("5","Wall sw","sw"),("15","Clear","sw"),
 ("17","UART TX","uart"),("16","UART RX","uart")]
eh=60+len(pins)*30; box(ex,ey,ew,eh,"ESP32-WROOM-32","#eef3ff")
txt(ex+12,ey+42,"5V",10,fill=C["5V"]); dot(ex,ey+38,C["5V"]); v5_tap(ex-18,ey+38); wire([(ex,ey+38),(ex-18,ey+38)],C["5V"])
txt(ex+12,ey+62,"GND",10,fill=C["GND"]); dot(ex,ey+58,C["GND"]); wire([(ex,ey+58),(ex-30,ey+58)],C["GND"]); gnd_tap(ex-30,ey+58)
P={}
for i,(g,lbl,net) in enumerate(pins):
    py=ey+52+i*30; dot(ex+ew,py,C[net]); txt(ex+ew-8,py+4,f"{g} {lbl}",10,"end"); P[g]=(ex+ew,py)

# Panel
box(380,170,160,100,"Touch panel","#eef6ff")
pxp=(380,204); pyp=(380,226); pxm=(380,248)
dot(*pxp,C["panel"]); txt(pxp[0]+8,pxp[1]+4,"X+ (pin4)",9.5)
dot(*pyp,C["panel"]); txt(pyp[0]+8,pyp[1]+4,"Y+ (pin3)",9.5)
dot(*pxm,C["panel"]); txt(pxm[0]+8,pxm[1]+4,"X-/Y- (pin2/1)",9.5)
route(P["18"],pxp,C["panel"],330); route(P["32"],pxp,C["panel"],338)
route(P["25"],pyp,C["panel"],330); route(P["35"],pyp,C["panel"],338)
route(P["23"],pxm,C["panel"],348); route(P["22"],pxm,C["panel"],352)

# MCP6002 + sheet/probe
box(380,320,250,150,"MCP6002 + sheet/probe","#fdf0f6")
txt(392,358,"sheet centre +5V, edges GND",9.5)
txt(392,378,"probe -> MCP6002 A -> 18k/33k",9.5)
m34=(380,408); dot(*m34,C["probe"]); txt(m34[0]+8,m34[1]+4,"-> GPIO34",9.5)
txt(392,436,"MCP6002 B -> CTRL_3V3 buffer",9.5)
mv3=(630,358); dot(*mv3,C["3V3"]); txt(mv3[0]-8,mv3[1]+4,"CTRL_3V3",9.5,"end")
route(P["34"],m34,C["probe"],340)
wire([mv3,(660,358),(660,96)],C["3V3"]); dot(660,96,C["3V3"]); v5_tap(410,320); gnd_tap(560,470)

# pots (7)
def pot(x,y,name,g):
    box(x,y,170,52,name,"#eef7f0"); top=(x,y+20); wip=(x,y+38); bot=(x+170,y+38)
    dot(*top,C["3V3"]); txt(top[0]+8,top[1]+4,"3V3",9)
    dot(*wip,C["pot"]); txt(wip[0]+8,wip[1]+4,f"wiper {g}",9)
    dot(*bot,C["GND"]); txt(bot[0]-8,bot[1]+4,"GND",9,"end"); return top,wip,bot
potdefs=[("Amplitude pot","13"),("Conductivity pot","33"),("Field-type pot","4"),
         ("Yaw pot","27"),("Pitch pot","14"),("Zoom pot","26"),("Zscale pot (VP)","36")]
pots=[]
for i,(nm,g) in enumerate(potdefs):
    p=pot(1080,170+i*64,nm,g); pots.append((p,g))
    wire([p[0],(p[0][0]-14,p[0][1]),(p[0][0]-14,96)],C["3V3"])
    wire([p[2],(p[2][0]+12,p[2][1])],C["GND"]); gnd_tap(p[2][0]+12,p[2][1])
    route(P[g],p[1],C["pot"],1004+i*5)

# switches (4)
def sw(x,y,name,g):
    box(x,y,170,44,name,"#f7f2ec"); a=(x,y+28); b=(x+170,y+28)
    dot(*a,C["sw"]); txt(a[0]+8,a[1]+4,g,9); dot(*b,C["GND"]); txt(b[0]-8,b[1]+4,"GND",9,"end"); return a
swdefs=[("Mode 1/2 switch","21"),("2D/3D switch","19"),("Wall/Source switch","5"),("Clear button","15")]
for i,(nm,g) in enumerate(swdefs):
    a=sw(1080,640+i*56,nm,g)
    route(P[g],a,C["sw"],1006+i*6)
    wire([(a[0]+170,a[1]),(a[0]+190,a[1])],C["GND"]); gnd_tap(a[0]+190,a[1])

# PYNQ
box(470,940,230,90,"PYNQ-Z1 (UART)","#eee")
pd0=(470,984); pd1=(470,1012)
dot(*pd0,C["uart"]); txt(pd0[0]+8,pd0[1]+4,"D0 (RX) <- TX",9.5)
dot(*pd1,C["uart"]); txt(pd1[0]+8,pd1[1]+4,"D1 (TX) -> RX",9.5)
route(P["17"],pd0,C["uart"],430); route(P["16"],pd1,C["uart"],440)

# legend
lx,ly=24,H-180; rect(lx,ly,300,140,fill="#fff"); txt(lx+10,ly+18,"Wire colours",11,weight="bold")
items=[("5V","+5 V"),("3V3","CTRL_3V3"),("GND","GND"),("panel","panel X/Y"),
       ("pot","pot wiper"),("sw","switch"),("probe","probe"),("uart","UART")]
for i,(k,lab) in enumerate(items):
    col=i//4; row=i%4; xx=lx+10+col*150; yy=ly+38+row*11
    el.append(f'<line x1="{xx}" y1="{yy-3}" x2="{xx+22}" y2="{yy-3}" stroke="{C[k]}" stroke-width="3"/>'); txt(xx+28,yy,lab,9.5)
txt(lx+10,ly+128,"GPIO36/VP = input-only; 5 & 15 are strapping (safe here)",8.5,fill="#555")
el.append("</svg>")
open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"breadboard_diagram.svg"),"w").write("\n".join(el))
print("wrote breadboard_diagram.svg")
