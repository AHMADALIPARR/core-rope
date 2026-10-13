#!/usr/bin/env python3
"""Educational core-rope ROM assembler, emulator, and wiring-map verifier.
This is a conceptual rope encoding, not an electrically validated Apollo replica.
"""
import argparse, json, re
from pathlib import Path
OPS={'NOP':0,'LDA':1,'ADD':2,'STA':3,'JMP':4,'JZ':5,'HLT':6}
MASK=0xFFF

def assemble(source):
    labels={}; entries=[]; pc=0
    for lineno, raw in enumerate(source.splitlines(),1):
        line=raw.split(';',1)[0].strip()
        if not line: continue
        if ':' in line:
            label,line=line.split(':',1); label=label.strip().upper()
            if not re.fullmatch(r'[A-Z_][A-Z_0-9]*',label) or label in labels: raise ValueError(f'line {lineno}: bad/duplicate label')
            labels[label]=pc; line=line.strip()
            if not line: continue
        parts=line.upper().split()
        if parts[0] not in OPS and parts[0]!='DAT': raise ValueError(f'line {lineno}: unknown instruction {parts[0]}')
        entries.append((lineno,parts));pc+=1
    if pc>16: raise ValueError('prototype ROM exceeds 16 words')
    words=[]
    for lineno,parts in entries:
        op=parts[0]; args=parts[1:]
        if op=='DAT':
            if len(args)!=1: raise ValueError(f'line {lineno}: DAT needs value')
            val=labels.get(args[0]);val=int(args[0],0) if val is None else val
            if not 0<=val<=MASK: raise ValueError('DAT out of range')
            words.append(val);continue
        if len(args)!=(0 if op in ('NOP','HLT') else 1): raise ValueError(f'line {lineno}: operand count')
        addr=0
        if args:
            addr=labels.get(args[0]);addr=int(args[0],0) if addr is None else addr
            if not 0<=addr<16: raise ValueError(f'line {lineno}: address out of range')
        words.append((OPS[op]<<8)|addr)
    return words+[0]*(16-len(words))

def wiring(words):
    # Each address selects a word line; bit=1 means thread passes through that bit's sense core.
    return [{'address':a,'word':f'{w:012b}','through_cores':[b for b in range(12) if w&(1<<b)],'around_cores':[b for b in range(12) if not w&(1<<b)]} for a,w in enumerate(words)]

def verify(words, rows):
    assert len(rows)==16
    for a,row in enumerate(rows):
        assert row['address']==a
        assert sorted(row['through_cores']+row['around_cores'])==list(range(12))
        assert not(set(row['through_cores'])&set(row['around_cores']))
        decoded=sum(1<<b for b in row['through_cores'])
        assert decoded==words[a],f'word {a} mismatch'
    return True

def run(words,max_steps=100):
    ram=list(words);pc=0;acc=0;trace=[]
    for _ in range(max_steps):
        if not 0<=pc<16: raise RuntimeError('PC outside ROM')
        ins=words[pc];op=ins>>8;addr=ins&0xFF
        if op not in OPS.values(): raise RuntimeError(f'bad opcode {op} at {pc}')
        if op in (1,2,3,4,5) and addr>=16: raise RuntimeError('bad address')
        trace.append({'pc':pc,'instruction':f'{ins:03X}','acc_before':acc})
        pc+=1
        if op==1: acc=ram[addr]
        elif op==2: acc=(acc+ram[addr])&MASK
        elif op==3: ram[addr]=acc
        elif op==4: pc=addr
        elif op==5 and acc==0: pc=addr
        elif op==6: return {'halted':True,'acc':acc,'ram':ram,'trace':trace}
    raise RuntimeError('execution step limit reached')

def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--out',type=Path,default=Path('build'));args=p.parse_args()
    words=assemble(args.source.read_text());rows=wiring(words);verify(words,rows);args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'rom.hex').write_text('\n'.join(f'{w:03X}' for w in words)+'\n')
    (args.out/'wiring.json').write_text(json.dumps({'encoding':'through=1, around=0; conceptual only','bit_order':'LSB core 0 to MSB core 11','rows':rows},indent=2)+'\n')
    result=run(words);(args.out/'trace.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'PASS: 16x12 ROM, wiring round-trip verified, halted={result["halted"]}, ACC={result["acc"]}')
if __name__=='__main__': main()
