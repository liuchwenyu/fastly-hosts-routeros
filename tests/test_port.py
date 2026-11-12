from pathlib import Path
import json
import re
import pytest
from reference_model import *
ROOT=Path(__file__).resolve().parents[1]

@pytest.mark.parametrize('text,expected',[
 ('cache-nrt-rjtf7700089-NRT','NRT'),
 ('t4_p, cache-nrt-rjaa8190044-NRT, cache-sin-wsat1880090-SIN, cache-tw-ZZZ1','SIN'),
 ('cache-tw-ZZZ1','?'),('', '?'),(None,'?'),
 ('cache-x-y-nrt','NRT'),('cache-sof-z-SOF, cache-itm-z-ITM','ITM'),
 ('not-cache-nrt-NRT','?'),('cache-a-SI','?')])
def test_pop(text,expected):assert pop_of(text)==expected

@pytest.mark.parametrize('headers',[
 ['Content-Type: text/plain','X-Served-By: cache-nrt-test-NRT'],
 ['x-served-by: cache-nrt-test-NRT'],
 {'X-Served-By':'cache-nrt-test-NRT'},
 {'x-served-by':'cache-nrt-test-NRT'}])
def test_headers(headers):assert header_of(headers,'X-Served-By')=='cache-nrt-test-NRT'

def test_header_preserves_semicolon_and_query():
 assert header_of(['Location: https://example.com/a;b?c=1&d=2'],'location')=='https://example.com/a;b?c=1&d=2'

@pytest.mark.parametrize('ip,suffix,expected',[
 ('146.75.48.133',159,'146.75.48.159'),('151.101.192.0',133,'151.101.192.133'),
 ('255.255.255.255',0,'255.255.255.0'),('0.0.0.0',255,'0.0.0.255')])
def test_suffix(ip,suffix,expected):assert same24(ip,suffix)==expected
@pytest.mark.parametrize('suffix',[-1,256,999])
def test_bad_suffix(suffix):
 with pytest.raises(ValueError):same24('1.1.1.1',suffix)

@pytest.mark.parametrize('cidr,count',[
 ('151.101.0.0/16',256),('146.75.0.0/17',128),('103.245.222.0/23',2),
 ('103.244.50.0/24',1),('10.0.0.0/15',512),('10.0.0.0/25',1),('10.0.0.133/32',1)])
def test_cidr_expansion(cidr,count):assert len(blocks([cidr]))==count

def test_overlapping_cidrs_dedup():assert len(blocks(['151.101.0.0/16','151.101.192.0/24']))==256

def test_long_prefix_membership_checked_before_suffix():
 assert candidate_ips(['10.0.0.0/25'],133)==[]
 assert candidate_ips(['10.0.0.128/25'],133)==['10.0.0.133']

def test_no_stride_sampling_or_fake_cap():
 ips=candidate_ips(['151.101.0.0/16'],133)
 assert len(ips)==256
 assert '151.101.1.133' in ips
 assert '151.101.192.133' in ips
 with pytest.raises(ValueError):blocks(['0.0.0.0/0'],8)

@pytest.mark.parametrize('pop,expected',[('SIN',False),('QPG',False),('?',False),('ZZZ1',False),('NRT',True),('ITM',True),('MAA',True),('DFW',True)])
def test_exclude(pop,expected):assert allowed(pop)==expected

def test_region_never_bypasses_exclusion():
 assert not allowed('SIN','SIN')
 assert not allowed('ITM','NRT')
 assert allowed('NRT','NRT')

def candidates():return [dict(ip='1.1.1.133',latencyUs=9000),dict(ip='2.2.2.133',latencyUs=1000)]

def test_rank_upstream_smooth_before_speed():
 out=rank(candidates(),{'1.1.1.133':[10000000]*3,'2.2.2.133':[20000000,1000000,20000000]})
 assert out[0]['ip']=='1.1.1.133'
 assert out[0]['smooth']==3
 assert out[0]['thresholdBps']==6000000

def test_rank_all_slow_uses_median():
 out=rank(candidates(),{'1.1.1.133':[1000000,1200000],'2.2.2.133':[2000000,2100000]})
 assert out[0]['ip']=='2.2.2.133'
 assert out[0]['smooth']==0

def test_rank_latency_fallback():assert rank(candidates(),{})[0]['ip']=='2.2.2.133'

def test_hysteresis_boundary():
 a=dict(smooth=3,valid=3,medianBps=10000000);b=dict(a,medianBps=12000000)
 assert sticky(a,b)
 assert not sticky(a,dict(b,medianBps=12000001))
 assert not sticky(dict(a,smooth=2),b)

@pytest.mark.parametrize('value,expected',[
 ('bytes 0-1023/8388608',dict(first=0,last=1023,total=8388608)),
 ('bytes 0-1023/*',None),('bytes */1024',None),('bytes 10-9/100',None),
 ('bytes 0-1024/1024',None)])
def test_range(value,expected):assert content_range(value)==expected

@pytest.mark.parametrize('url',[
 'http://example.com/','https://u:p@example.com/','https://example.com:8443/a',
 'https://127.0.0.1/','https://example.com/\r\nHost:x','https://example.com/#x',
 'https://-bad.example.com/'])
def test_unsafe_url(url):
 with pytest.raises(ValueError):parse_url(url)

def test_signed_query_unchanged():
 assert parse_url('https://release-assets.githubusercontent.com/a?sig=abc%2Fdef&x=1')==('release-assets.githubusercontent.com','/a?sig=abc%2Fdef&x=1')

@pytest.mark.parametrize('key,count',[('github',2),('x',1),('twitch',5)])
def test_builtin_coverage(key,count):assert len(BUILTINS[key])==count

def test_sources_contain_all_upstream_aliases():
 source=(ROOT/'routeros/FHR-config.rsc').read_text(encoding='utf-8')
 for group in BUILTINS.values():
  for host,suffix in group.items():assert f'"{host}"={suffix}' in source
 assert '"releaseRepos"={"ollama/ollama";"cli/cli"' in source

@pytest.mark.parametrize('phase',['stage','disable','enable'])
def test_failed_dns_transaction_recovers(phase):
 original=[Record('raw.githubusercontent.com','185.199.108.133',comment='Fastly-Pilot-Raw'),Record('raw.githubusercontent.com','2606:50c0::',type='AAAA'),Record('example.com','192.0.2.1')]
 dns=DNSModel(original)
 with pytest.raises(RuntimeError):dns.apply('github','151.101.192.133',BUILTINS['github'],fail_at=phase)
 assert dns.records==original

def test_dns_preserves_aaaa_and_unrelated_records_and_restore():
 original=[Record('raw.githubusercontent.com','185.199.108.133',comment='FastlyROS:auto:raw:v0.4'),Record('raw.githubusercontent.com','2606:50c0::',type='AAAA'),Record('example.com','192.0.2.1')]
 dns=DNSModel(original);dns.apply('github','151.101.192.133',BUILTINS['github'])
 assert len([r for r in dns.records if r.type=='AAAA'])==1
 assert next(r for r in dns.records if r.name=='raw.githubusercontent.com' and r.type=='A').address=='151.101.192.133'
 dns.restore();assert sorted(map(repr,dns.records))==sorted(map(repr,original))

def test_dns_does_not_overwrite_foreign_a():
 dns=DNSModel([Record('raw.githubusercontent.com','192.0.2.9',comment='manual')])
 with pytest.raises(ValueError):dns.apply('github','151.101.192.133',BUILTINS['github'])
 assert dns.records[0].address=='192.0.2.9'

def test_twitch_uses_both_suffixes():
 dns=DNSModel();dns.apply('twitch','146.75.48.214',BUILTINS['twitch'])
 assert next(r.address for r in dns.records if r.name=='k.twitchcdn.net')=='146.75.48.167'
 assert len(dns.records)==5

def test_repeated_apply_idempotent_record_count():
 dns=DNSModel()
 for _ in range(3):dns.apply('github','151.101.192.133',BUILTINS['github'])
 assert len(dns.records)==2

def test_native_array_append_regression_guard():
 for p in (ROOT/'routeros').glob('*.rsc'):
  assert not re.search(r':set\s+\w+\s+\(\$\w+,\s*\$(row|result|compact)\)',p.read_text(encoding='utf-8')),p.name

def test_native_exact_a_only_and_tls_always_enabled():
 allcode='\n'.join(p.read_text(encoding='utf-8') for p in (ROOT/'routeros').glob('*.rsc'))
 assert 'check-certificate=no' not in allcode
 assert '/ip firewall nat add' not in allcode
 assert '/ip firewall mangle add' not in allcode
 assert '/ip route add' not in allcode
 assert '/ip dns set' not in allcode
 assert 'type=AAAA' not in allcode
 assert 'FastlyROS:auto:' in allcode
 assert '[:pick $c 0 15]' in allcode

@pytest.mark.parametrize('command',['apply','test','scan','region','switch','list','status','health','enable','disable','remove','add','set','set-test-url','set-probe-path','rollback','restore','purge','enable-schedule','disable-schedule','check-update'])
def test_public_commands_implemented(command):
 source=(ROOT/'routeros/FHR-commands.rsc').read_text(encoding='utf-8')
 assert f'$action = "{command}"' in source


def decode_ros_string(token):
    """Only decode the exact escapes emitted by tools/build.py, not RouterOS code."""
    out=[]; i=0
    mapping={'n':'\n','r':'\r','t':'\t','\\':'\\','"':'"','$':'$'}
    while i<len(token):
        if token[i]=='\\':
            i+=1
            assert token[i] in mapping
            out.append(mapping[token[i]])
        else:out.append(token[i])
        i+=1
    return ''.join(out)


def test_single_file_installer_contains_exact_modular_sources():
    import hashlib,json
    text=(ROOT/'FHR-install-all.rsc').read_text(encoding='utf-8')
    found={}
    pattern=r':local source "((?:\\.|[^"\\])*)"\n.*?\n    :set \(\$FHRInstallSources->"([^"]+)"\) \$source'
    for match in re.finditer(pattern,text):
        source,key=decode_ros_string(match.group(1)),match.group(2)
        found[key]=source
        assert source==(ROOT/f'routeros/FHR-{key}.rsc').read_text(encoding='utf-8'),key
        assert len(source.encode())<57000
        assert len(match.group(0).encode())<60000
    expected=json.loads((ROOT/'manifests/embedded-sources.json').read_text(encoding='utf-8'))
    assert set(found)==set(expected)
    assert len(found)==23
    for key,source in found.items():assert hashlib.sha256(source.encode()).hexdigest()==expected[key]


def test_installer_does_not_run_dns_apply_or_enable_scheduler():
    text=(ROOT/'FHR-install-all.rsc').read_text(encoding='utf-8')
    controller=text.rsplit('    :local parts ',1)[1]
    assert '/system script run FHR.apply\n' not in controller
    assert '/system script run FHR.enable-schedule\n' not in controller
    assert '/system script run FHR.selftest' in controller


def test_transaction_journal_restores_selection_metadata():
    source=(ROOT/'routeros/FHR-dns.rsc').read_text(encoding='utf-8')
    assert '"oldCurrent"=$oldCurrent' in source
    assert '"oldPrevious"=$oldPrevious' in source
    assert '($tx->"oldCurrent")' in source
    assert '($tx->"oldPrevious")' in source


def test_live_scheduler_commands_check_ownership():
    source=(ROOT/'routeros/FHR-commands.rsc').read_text(encoding='utf-8')
    block=source.split(':global FHRSchedule do={',1)[1].split(':global FHRDispatch do={',1)[0]
    assert 'comment] != "FHR native v1"' in block
