import sys,glob,os
from PIL import Image, ImageDraw
files=sorted(glob.glob(sys.argv[1]+'/*.png')); cols=int(sys.argv[3]); w=300
ims=[Image.open(f).convert('RGB') for f in files]
h=max(int(i.height*w/i.width) for i in ims)
rows=(len(ims)+cols-1)//cols
S=Image.new('RGB',(cols*(w+10),rows*(h+30)),'white'); d=ImageDraw.Draw(S)
for k,(f,i) in enumerate(zip(files,ims)):
    x=(k%cols)*(w+10); y=(k//cols)*(h+30)
    S.paste(i.resize((w,int(i.height*w/i.width))),(x,y+20)); d.text((x+4,y+4),os.path.basename(f),fill='black')
S.save(sys.argv[2])
