# Generates nc.ans, the fastfetch logo: pixel-art black hardtop MX-5 NC
# rendered as truecolor half-blocks. Usage: python3 nc-logo.py nc.ans /dev/null
import sys
W,H=52,18
C={'.':None,'b':(0x2b,0x33,0x3d),'l':(0x3c,0x48,0x54),'d':(0x1c,0x22,0x29),'e':(0x8a,0x9c,0xa3),'w':(0x34,0x4a,0x55),'W':(0x8f,0xc1,0xcc),
   't':(0xef,0x2f,0x6e),'h':(0xe6,0xf2,0xff),'k':(0x0b,0x0e,0x12),'r':(0x71,0x86,0x8b),'g':(0x6a,0x16,0x34),'G':(0x3a,0x0c,0x1e)}
P=[['.']*W for _ in range(H)]
def put(x,y,c):
    if 0<=x<W and 0<=y<H: P[y][x]=c
def span(y,a,b,c):
    for x in range(a,b+1): put(x,y,c)
# hardtop roof (rear-biased cabin, front = right)
span(2,18,27,'e')
span(3,15,17,'e'); span(3,18,28,'b'); span(3,29,30,'e')
span(4,13,14,'e'); span(4,15,17,'b'); span(4,18,24,'w'); span(4,25,25,'b'); span(4,26,30,'w'); span(4,31,32,'e')
span(4,27,28,'W')
span(5,11,12,'e'); span(5,13,16,'b'); span(5,17,24,'w'); span(5,25,25,'b'); span(5,26,32,'w'); span(5,33,35,'e')
span(5,28,29,'W')
# body: short deck left, long hood right
span(6,3,10,'e'); span(6,11,36,'b'); span(6,37,46,'e')
span(7,2,48,'b'); span(7,2,4,'t'); span(7,47,49,'h')
span(8,1,50,'b'); span(8,1,2,'t'); span(8,49,50,'h')
span(9,1,50,'b'); span(9,6,46,'l')
span(10,1,50,'b')
span(11,1,50,'b'); span(12,2,49,'d'); span(13,16,34,'d')
for y in range(7,12): put(31,y,'d')
# wheels
for cx in (11,40):
    for y in range(7,18):
        for x in range(cx-7,cx+8):
            d=((x-cx+0.5)**2+(y-13.5)**2)**0.5
            if d<=4.1: put(x,y,'k' if (d<=1.0 or d>3.0) else 'r')
            elif d<=5.2 and P[y][x] in 'bdl': put(x,y,'.')
# taillight glow on the road
span(17,0,5,'g'); span(17,6,8,'G')
def fg(c): return f'\x1b[38;2;{c[0]};{c[1]};{c[2]}m'
def bg(c): return f'\x1b[48;2;{c[0]};{c[1]};{c[2]}m'
out=[]
for y in range(0,H,2):
    line=''
    for x in range(W):
        t,b=C[P[y][x]],C[P[y+1][x]]
        if t is None and b is None: line+='\x1b[0m '
        elif t is None: line+='\x1b[0m'+fg(b)+'▄'
        elif b is None: line+='\x1b[0m'+fg(t)+'▀'
        else: line+=fg(t)+bg(b)+'▀'
    out.append(line.rstrip()+'\x1b[0m')
open(sys.argv[1],'w').write('\n'.join(out)+'\n')
# preview
with open(sys.argv[2],'w') as f:
    f.write(f'P3 {W} {H} 255\n')
    for row in P:
        f.write(' '.join('%d %d %d'%(C[c] or (0x13,0x17,0x1d)) for c in row)+'\n')
