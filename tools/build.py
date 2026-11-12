#!/usr/bin/env python3
"""Build native loader/wrappers/installer; no target-side Python dependency."""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'routeros'
MODULES=['config','core','storage','network','benchmarks','discovery','dns','engine','commands']
config_text = (OUT / 'FHR-config.rsc').read_text(encoding='utf-8')
version_match = re.search(r'^\s*"version"="(\d+\.\d+\.\d+)";$', config_text, re.MULTILINE)
if version_match is None:
    raise ValueError('FHR-config.rsc must declare a release version')
VERSION = version_match.group(1)

def write(name: str, s: str) -> None:
    (OUT/name).write_text(s.rstrip()+'\n', encoding='utf-8', newline='\n')

load='\n'.join(f':onerror fhrModuleError in={{/system script run FHR.{x}}} do={{:error ("FHR.load/{x}: " . $fhrModuleError)}}' for x in MODULES)
load+='\n:global FHRLoadSettings; :onerror e in={$FHRLoadSettings} do={:error ("FHR.load/settings: " . $e)}\n:global FHRValidateConfig; :onerror e in={$FHRValidateConfig} do={:error ("FHR.load/validation: " . $e)}'
write('FHR-load.rsc',load)
for action in ['apply','test','scan','status','health','restore','purge','enable-schedule','disable-schedule']:
    write('FHR-'+action+'.rsc',f'/system script run FHR.load\n:global FHR\n$FHR action="{action}"')
write('FHR-help.rsc',r'''
:put "Fastly Hosts RouterOS @VERSION@ (reference: upstream Python 0.8.3)"
:put "Quick commands: /system script run FHR.apply | FHR.status | FHR.restore"
:put "Load API in a new terminal: /system script run FHR.load; :global FHR"
:put "$FHR action=apply [service=github|x|twitch|custom.DOMAIN] [refresh=true]"
:put "$FHR action=test   -- selects but does not change DNS"
:put "$FHR action=scan   -- full discovery, updates scan cache, not DNS"
:put "$FHR action=region region=NRT -- fresh discovery, select and apply this POP"
:put "$FHR action=switch region=NRT -- revalidate cached routes, select and apply"
:put "$FHR action=list [service=github] -- cached POP inventory"
:put "$FHR action=add domain=video.twimg.com [url=https://video.twimg.com/PATH]"
:put "$FHR action=set-test-url service=custom.video.twimg.com url=https://video.twimg.com/PATH"
:put "$FHR action=set-probe-path service=x value=/profile_images/KNOWN_IMAGE.jpg"
:put "$FHR action=enable|disable|remove service=KEY"
:put "$FHR action=set property=parallel value=8 -- typed configuration values"
:put "$FHR action=rollback service=github -- revalidate previous route first"
:put "$FHR action=restore -- stop schedules and restore pre-install managed names"
:put "$FHR action=purge -- restore DNS and remove state; native scripts remain"
:put "$FHR action=enable-schedule|disable-schedule|health|status|check-update"
:put "All exact A-record changes are owned by comment prefix FHR:auto:."
:put "Default excludes SIN/QPG. No eligible candidate: keep existing DNS."
:put "Health fail-open may restore an upstream answer in Singapore; it is not a geo firewall."
'''.replace('@VERSION@', VERSION).replace(':put "$FHR', r':put "\$FHR'))
write('FHR-doctor.rsc',r'''
/system resource print
/ip dns print
/ip dhcp-server network print detail
/ip firewall mangle print detail where chain=output
/ip route print detail where dst-address="0.0.0.0/0"
/ip dns static print detail where comment~"^FHR:auto:"
/tool netwatch print detail where comment="FHR:temporary-tcp"
/system scheduler print detail where name~"^FHR[.]"
:put "A DNS override affects only clients querying this router. These commands change no configuration."
''')
write('FHR-uninstall.rsc',r'''
/system script run FHR.purge
:foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
    :foreach fhrScheduleId in=[/system scheduler find where name=$fhrScheduleName] do={
        :if (([/system scheduler get $fhrScheduleId name] = $fhrScheduleName) && ([/system scheduler get $fhrScheduleId comment] = "FHR native v1")) do={/system scheduler remove $fhrScheduleId}
    }
}
:foreach id in=[/system script find where comment="FHR native v1"] do={/system script remove $id}
:put "FHR native scripts removed. Uploaded source files were retained."
''')
# Selftest is not a wrapper: its source uses globals loaded by the installer.
items=MODULES+['load','selftest','apply','test','scan','status','health','restore','purge','enable-schedule','disable-schedule','help','doctor','uninstall']
arr=';'.join('"'+x+'"' for x in items)
installer=r'''
# Upload all FHR-*.rsc files from routeros/ to the SAME WinBox Files directory.
# Default is Files root. For a folder upload, change this one prefix, e.g. "fhr/".
# Use distinct lookup variables for RouterOS name properties.
{
    :local prefix ""
    :local parts {@PARTS@}
    :local sources [:toarray ""]
    :put "FHR installer @VERSION@: checking sources and exact ownership before changes"
    :foreach part in=$parts do={
        :local path ($prefix . "FHR-" . $part . ".rsc")
        :local fhrSourceIds [/file find where name=$path]
        :if ([:len $fhrSourceIds] != 1) do={:error ("Missing or ambiguous source file: " . $path)}
        :if ([/file get $fhrSourceIds size] > 57000) do={:error ("Source too large: " . $path)}
        :local source [/file get $fhrSourceIds contents]
        :onerror err in={:local compiled [:parse $source]} do={:error ("Compile check failed in " . $path . ": " . $err)}
        :set ($sources->$part) $source
        :local fhrScriptName ("FHR." . $part)
        :local fhrScriptIds [/system script find where name=$fhrScriptName]
        :local fhrExactCount 0
        :foreach fhrScriptId in=$fhrScriptIds do={
            :if ([/system script get $fhrScriptId name] != $fhrScriptName) do={:error ("Script lookup returned a different name: " . $fhrScriptName)}
            :set fhrExactCount ($fhrExactCount + 1)
            :if ([/system script get $fhrScriptId comment] != "FHR native v1") do={:error ("Unmanaged script already uses name " . $fhrScriptName)}
        }
        :if ($fhrExactCount > 1) do={:error ("Duplicate exact script name: " . $fhrScriptName . "; count=" . $fhrExactCount)}
    }
    # Validate all scheduler ownership before disabling any existing schedule.
    :foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
        :local fhrScheduleIds [/system scheduler find where name=$fhrScheduleName]
        :if ([:len $fhrScheduleIds] > 1) do={:error ("Duplicate exact scheduler name: " . $fhrScheduleName)}
        :foreach fhrScheduleId in=$fhrScheduleIds do={
            :if ([/system scheduler get $fhrScheduleId name] != $fhrScheduleName) do={:error ("Scheduler lookup returned a different name: " . $fhrScheduleName)}
            :if ([/system scheduler get $fhrScheduleId comment] != "FHR native v1") do={:error ("Unmanaged scheduler uses " . $fhrScheduleName)}
        }
    }
    # Avoid two versions writing the same hostnames. Retain the old schedule disabled.
    :foreach fhrLegacyId in=[/system scheduler find where name="FastlyROS-auto-v0.4"] do={
        :if (([/system scheduler get $fhrLegacyId name] = "FastlyROS-auto-v0.4") && ([/system scheduler get $fhrLegacyId comment] = "FastlyROS:auto:v0.4")) do={/system scheduler disable $fhrLegacyId; :put "Disabled legacy v0.4 scheduler"}
    }
    :foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
        :foreach fhrScheduleId in=[/system scheduler find where name=$fhrScheduleName] do={
            :if (([/system scheduler get $fhrScheduleId name] != $fhrScheduleName) || ([/system scheduler get $fhrScheduleId comment] != "FHR native v1")) do={:error "Scheduler ownership changed during install"}
            /system scheduler disable $fhrScheduleId
            /system scheduler set $fhrScheduleId policy=ftp,read,write,policy,test,sensitive
        }
    }
    :foreach part in=$parts do={
        :local fhrScriptName ("FHR." . $part)
        :local fhrScriptIds [/system script find where name=$fhrScriptName]
        :if ([:len $fhrScriptIds] > 1) do={:error ("Duplicate exact script name during update: " . $fhrScriptName)}
        :if ([:len $fhrScriptIds] = 0) do={
            /system script add name=$fhrScriptName comment="FHR native v1" policy=ftp,read,write,policy,test,sensitive dont-require-permissions=no source=($sources->$part)
        } else={
            :foreach fhrScriptId in=$fhrScriptIds do={
                :if (([/system script get $fhrScriptId name] != $fhrScriptName) || ([/system script get $fhrScriptId comment] != "FHR native v1")) do={:error "Script ownership changed during install"}
                /system script set $fhrScriptId source=($sources->$part) policy=ftp,read,write,policy,test,sensitive dont-require-permissions=no
            }
        }
    }
    /system script run FHR.load
    /system script run FHR.selftest use-script-permissions
    :put "INSTALLED @VERSION@. No DNS switch was made by the installer."
    :put "New installation: run /system script run FHR.apply when ready to select DNS targets."
    :put "Existing installation: check FHR.doctor first. To resume automatic operation, run /system script run FHR.enable-schedule."
}
'''.replace('@PARTS@',arr).replace('@VERSION@', VERSION)
write('FHR-install.rsc',installer)
print('Built',len(list(OUT.glob('*.rsc'))),'native source files')

# One-file import: each module is an independent <64KB command block.
# Only the installer reads this whole file via /import; no giant :execute or
# /file get contents operation is used. Source strings decode to exact originals.
def ros_quote(source: str) -> str:
    return ('"' + source.replace('\\','\\\\').replace('"','\\"')
            .replace('$','\\$').replace('\r','\\r').replace('\n','\\n')
            .replace('\t','\\t') + '"')

blocks = [r'''# Fastly Hosts RouterOS @VERSION@ single-file installer.
# Import installs native scripts and runs local selftests. It does NOT apply DNS.
# Based on AFAlimru/fastly-hosts-adjust v0.8.3 (MIT). See the accompanying LICENSE.
:global FHRInstallSources [:toarray ""]
'''.replace('@VERSION@', VERSION)]
for part in items:
    source=(OUT/f'FHR-{part}.rsc').read_text(encoding='utf-8')
    block=('{'+'\n    :global FHRInstallSources\n'
        +'    :local source '+ros_quote(source)+'\n'
        +'    :onerror err in={:local compiled [:parse $source]} do={:error ("Compile check failed: FHR.'+part+': " . $err)}\n'
        +'    :set ($FHRInstallSources->"'+part+'") $source\n}\n')
    if len(block.encode('utf-8')) >= 60000:
        raise ValueError(f'{part}: encoded import block is too large')
    blocks.append(block)
# Reuse the same owner checks and commit logic; source has already been parsed.
controller=installer[installer.index('{\n'):]
controller=controller.replace('    :local prefix ""\n','')
controller=controller.replace('    :local sources [:toarray ""]', '    :global FHRInstallSources\n    :local sources $FHRInstallSources')
a=controller.index('        :local path ($prefix')
b=controller.index('        :local fhrScriptName ("FHR." . $part)',a)
controller=controller[:a]+'''        :if ([:typeof ($sources->$part)] != "str") do={:error ("Embedded source missing: " . $part)}
'''+controller[b:]
controller=controller.replace('    /system script run FHR.load', '    :set FHRInstallSources [:toarray ""]\n    /system script run FHR.load',1)
blocks.append(controller)
(ROOT/'FHR-install-all.rsc').write_text('\n'.join(blocks),encoding='utf-8', newline='\n')
# A source/decoded hash manifest makes reproducible packaging easy to inspect.
manifests = ROOT / 'manifests'
manifests.mkdir(exist_ok=True)
(manifests / 'embedded-sources.json').write_text(json.dumps({p:hashlib.sha256((OUT/f'FHR-{p}.rsc').read_bytes()).hexdigest() for p in items},indent=2)+'\n', encoding='utf-8', newline='\n')
print('Built single-file installer:',(ROOT/'FHR-install-all.rsc').stat().st_size,'bytes;',len(items),'embedded scripts')
