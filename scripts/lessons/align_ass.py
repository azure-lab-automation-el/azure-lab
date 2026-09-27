# Builds Hebrew ASS subtitles for one lesson: cue text from the final narration script,
# timing from faster-whisper word timestamps (proportional char mapping) snapped to silences.
import re,subprocess,json,sys,os
L,src,out=sys.argv[1],sys.argv[2],sys.argv[3]
texts=json.load(open(f'{src}/narration-final.json'))[L]; texts=[texts[str(i)] for i in range(1,9)]
import hashlib
MODEL=os.environ.get('WHISPER_MODEL','medium'); CACHE=os.environ.get('ALIGN_CACHE','.align-cache'); os.makedirs(CACHE,exist_ok=True)
_model=None
def words_for(a):
    # Per-audio transcript cache (key = audio bytes + model + decode settings): unchanged narration skips Whisper entirely.
    global _model
    k=hashlib.sha256(open(a,'rb').read()+f'|{MODEL}|int8|beam5|he'.encode()).hexdigest()[:24]; f=f'{CACHE}/{k}.json'
    if os.path.exists(f): print(f'align-cache hit {os.path.basename(a)}',flush=True); return [tuple(w) for w in json.load(open(f))]
    if _model is None:
        from faster_whisper import WhisperModel
        _model=WhisperModel(MODEL,device='cpu',compute_type='int8',cpu_threads=os.cpu_count() or 4)
    segs,_=_model.transcribe(a,language='he',word_timestamps=True,beam_size=5,vad_filter=False)
    w=[(x.start,x.end,x.word.strip()) for s in segs for x in (s.words or []) if x.word.strip()]
    json.dump(w,open(f,'w'),ensure_ascii=False); print(f'align-cache miss {os.path.basename(a)}',flush=True); return w
def dur(a): return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',a]))
def sil(a):
    o=subprocess.run(['ffmpeg','-i',a,'-af','silencedetect=n=-35dB:d=0.15','-f','null','-'],capture_output=True,text=True).stderr
    st=[float(x) for x in re.findall(r'silence_start: ([\d.]+)',o)]; en=[float(x) for x in re.findall(r'silence_end: ([\d.]+)',o)]
    return [((s+e)/2,e-s) for s,e in zip(st,en) if s>0.3]
def split(t):
    parts=re.split(r'(?<=[.:])\s+',t); out=[]
    for p in parts:
        while len(p)>70 and ', ' in p[10:-10]:
            idx=[m.start() for m in re.finditer(', ',p)]; mid=min(idx,key=lambda i:abs(i-len(p)/2)); out.append(p[:mid+1]); p=p[mid+2:]
            if len(p)<=70: break
        out.append(p)
    m=[]
    for p in out:
        if m and len(m[-1])<16 and m[-1].endswith(':'): m[-1]=m[-1]+' '+p
        elif m and len(p)<16 and p.endswith('.') and len(m[-1])+len(p)<95: m[-1]=m[-1]+' '+p
        else: m.append(p)
    return m
def ts(x):
    h=int(x//3600);m=int(x%3600//60);s=x%60; return f'{h}:{m:02d}:{s:05.2f}'
def srt(x):
    ms=int(round(x*1000)); return f'{ms//3600000:02d}:{ms//60000%60:02d}:{ms//1000%60:02d},{ms%1000:03d}'
ass=['[Script Info]','ScriptType: v4.00+','PlayResX: 1920','PlayResY: 1080','WrapStyle: 0','ScaledBorderAndShadow: yes','','[V4+ Styles]','Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding','Style: Default,DejaVu Sans,56,&H00FFFFFF,&H000000FF,&H00251F21,&H99000000,-1,0,0,0,100,100,0,0,3,10,0,2,160,160,40,1','','[Events]','Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text']
off=0; rows=[]; srt_l=[]; report=[]
for i,t in enumerate(texts,1):
    a=f'{src}/{L}-{i:02d}.flac'; d=dur(a); S=sil(a); cues=split(t)
    words=words_for(a)
    report.append({'part':i,'heard':' '.join(w[2] for w in words),'words':[[round(a,2),round(b,2),t] for a,b,t in words]})
    # Token alignment: script tokens vs heard tokens (Hebrew words match exactly; English terms are bridged by the matcher).
    import difflib
    norm=lambda x: re.sub(r'^[וה]?-?','',re.sub(r'[^\w\u0590-\u05ff-]+','',x.lower()))
    htok=[norm(x[2]) for x in words]
    ctoks=[[norm(x) for x in c.split()] for c in cues]
    stok=[x for ct in ctoks for x in ct]
    sm=difflib.SequenceMatcher(None,stok,htok,autojunk=False)
    m={}
    for bl in sm.get_matching_blocks():
        for k in range(bl.size): m[bl.a+k]=bl.b+k
    def start_of(si):
        # heard index for script token si: exact match, else interpolate from neighbours
        if si in m: return words[m[si]][0]
        lo=max([k for k in m if k<si],default=None); hi=min([k for k in m if k>si],default=None)
        if lo is None and hi is None: return d*si/max(len(stok),1)
        if lo is None: return words[m[hi]][0]
        if hi is None: return words[m[lo]][1]
        tl,th=words[m[lo]][1],words[m[hi]][0]
        return tl+(th-tl)*(si-lo)/(hi-lo)
    bounds=[]; si=0
    for ct in ctoks[:-1]:
        si+=len(ct); target=start_of(si)
        cand=[x for x in S if target-0.9<=x[0]<=target+0.25 and (not bounds or x[0]>bounds[-1]+0.8)]
        b=max(cand,key=lambda x:x[0])[0] if cand else target-0.1
        if bounds and b<=bounds[-1]+0.8: b=bounds[-1]+0.8
        bounds.append(b)
    edges=[0]+bounds+[d]
    for c,(s,e) in zip(cues,zip(edges,edges[1:])):
        ass.append(f'Dialogue: 0,{ts(off+s)},{ts(off+e)},Default,,0,0,0,,\u202b{c}\u202c')
        srt_l.append(f'{len(srt_l)+1}\n{srt(off+s)} --> {srt(off+e)}\n\u202b{c}\u202c\n')
        heard=' '.join(x[2] for x in words if x[0]>=s-0.15 and x[1]<=e+0.15)
        rows.append({'part':i,'start':round(off+s,2),'end':round(off+e,2),'text':c,'heard':heard})
    off+=d
open(f'{out}/{L}.ass','w').write('\n'.join(ass)+'\n')
open(f'{out}/{L}.srt','w').write('\n'.join(srt_l))
json.dump({'cues':rows,'parts':report},open(f'{out}/{L}-align.json','w'),ensure_ascii=False,indent=1)
print(L,len(rows),'cues',round(off,2),'s')
