"""Executable specification for native-port algorithm tests.
This does not execute RouterOS. Source: upstream v0.8.3, MIT AFAlimru.
"""
from __future__ import annotations
from dataclasses import dataclass
from copy import deepcopy
from ipaddress import IPv4Address, IPv4Network
from statistics import median
from urllib.parse import urlsplit
import re

BUILTINS = {
 'github': {'raw.githubusercontent.com':133,'release-assets.githubusercontent.com':133},
 'x': {'pbs.twimg.com':159},
 'twitch': {'www.twitch.tv':214,'gql.twitch.tv':214,'static-cdn.jtvnw.net':214,'assets.twitch.tv':214,'k.twitchcdn.net':167},
}

def pop_of(value: str | None) -> str:
    answer='?'
    for item in (value or '').split(','):
        bits=item.strip().split('-')
        if len(bits)>=3 and bits[0]=='cache' and re.fullmatch('[A-Za-z]{3}',bits[-1]):answer=bits[-1].upper()
    return answer

def header_of(headers, wanted: str) -> str:
    if isinstance(headers,dict):
        return next((str(v).strip() for k,v in headers.items() if str(k).lower()==wanted.lower()),'')
    for line in headers:
        k,sep,v=str(line).partition(':')
        if sep and k.strip().lower()==wanted.lower():return v.strip()
    return ''

def same24(ip: str,suffix: int)->str:
    n=int(IPv4Address(ip))
    if not 0<=suffix<=255:raise ValueError('invalid suffix')
    return str(IPv4Address(n//256*256+suffix))

def blocks(cidrs:list[str], maximum:int=16384)->list[str]:
    out=[];seen=set()
    for cidr in cidrs:
        net=IPv4Network(cidr,strict=False)
        lo=int(net.network_address)//256*256
        hi=int(net.broadcast_address)//256*256
        for n in range(lo,hi+1,256):
            if n not in seen:
                seen.add(n);out.append(str(IPv4Address(n)))
                if len(out)>maximum:raise ValueError('no silent truncation')
    return out

def candidate_ips(cidrs:list[str],suffix:int)->list[str]:
    nets=[IPv4Network(x,strict=False) for x in cidrs]
    return [same24(b,suffix) for b in blocks(cidrs) if any(IPv4Address(same24(b,suffix)) in n for n in nets)]

def allowed(pop: str,region:str='',excluded=('SIN','QPG'))->bool:
    return bool(re.fullmatch('[A-Z]{3}',pop)) and pop not in excluded and (not region or region==pop)

def rank(rows, samples, floor=3000000, percent=30):
    peak=max((n for vs in samples.values() for n in vs),default=0)
    threshold=max(peak*percent//100,floor)
    out=[]
    for item in rows:
        row=deepcopy(item);vs=samples.get(row['ip'],[])
        row.update(smooth=sum(n>=threshold for n in vs),medianBps=int(median(vs)) if vs else 0,thresholdBps=threshold)
        out.append(row)
    return sorted(out,key=lambda r:(-r['smooth'],-r['medianBps'],r['latencyUs'],int(IPv4Address(r['ip']))))

def sticky(current, best, percent=20):
    return (current['smooth']==best['smooth'] and current['valid']>=best['valid'] and current['medianBps']>0
            and best['medianBps']*100<=current['medianBps']*(100+percent))

def content_range(text):
    match=re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)',text)
    if not match:return None
    a,b,c=map(int,match.groups())
    return dict(first=a,last=b,total=c) if 0<=a<=b<c else None

def parse_url(url):
    p=urlsplit(url)
    if p.scheme!='https' or p.username or p.password or p.port or p.fragment or '\r' in url or '\n' in url:raise ValueError('unsafe URL')
    labels=(p.hostname or '').split('.')
    if len(labels)<2 or not re.fullmatch('[a-z]{2,63}',labels[-1]):raise ValueError('invalid hostname')
    for label in labels:
        if len(label)>63 or not re.fullmatch('[a-z0-9](?:[a-z0-9-]*[a-z0-9])?',label):raise ValueError('invalid label')
    return p.hostname, (p.path or '/')+('?' + p.query if p.query else '')

@dataclass(eq=True)
class Record:
    name:str
    address:str
    type:str='A'
    comment:str=''
    disabled:bool=False

class DNSModel:
    """Transaction design tests; not an emulation of /ip dns static."""
    def __init__(self,records=()):self.records=deepcopy(list(records));self.before={};self.previous={}
    @staticmethod
    def owned(r):return r.comment.startswith('FHR:auto:')
    @staticmethod
    def legacy(r):return r.comment.startswith('FastlyROS:auto:') or r.comment in ('Fastly-Pilot-Raw','Fastly-Pilot-raw')
    def apply(self,key,ip,aliases,fail_at=None):
        snapshot=deepcopy(self.records)
        names=set(aliases)
        active=[r for r in self.records if r.name in names and r.type=='A' and not r.disabled]
        if any(not(self.owned(r) or self.legacy(r)) for r in active):raise ValueError('unmanaged A conflict')
        for h in names:
            if h not in self.before:self.before[h]=deepcopy([r for r in self.records if r.name==h and r.type=='A' and self.legacy(r)])
        try:
            if fail_at=='stage':raise RuntimeError('injected stage')
            self.records=[r for r in self.records if not(r.name in names and r.type=='A' and (self.owned(r) or self.legacy(r)))]
            if fail_at=='disable':raise RuntimeError('injected disable')
            for h,suffix in aliases.items():self.records.append(Record(h,same24(ip,suffix),comment=f'FHR:auto:{key}:{h}'))
            if fail_at=='enable':raise RuntimeError('injected enable')
            self.previous[key]=snapshot
        except Exception:
            self.records=snapshot
            raise
    def restore(self):
        self.records=[r for r in self.records if not self.owned(r)]
        for records in self.before.values():
            for record in records:
                if record not in self.records:self.records.append(deepcopy(record))
        self.before={}
