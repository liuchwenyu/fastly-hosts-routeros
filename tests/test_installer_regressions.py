
"""Static regression checks for RouterOS installation and ownership."""
from pathlib import Path
import importlib.util
import re
import pytest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('fhr_static_check',ROOT/'tools/check_rsc.py')
check=importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

@pytest.mark.parametrize('code',[
    ':local name "FHR.config"; :put [/system script find where name=$name]',
    ':local name "FHR.config"; :put [/system script find name=$name]',
    ':foreach name in={"FHR.auto"} do={/system scheduler disable [find where name=$name]}',
    ':local comment "FHR native v1"; :put [/system script find where comment=$comment]',
    ':local type "ether1"; /interface print where name=$type',
])
def test_property_shadow_guard_rejects_ambiguous_queries(code):
    assert check.query_shadow_issues(code)

@pytest.mark.parametrize('code',[
    ':local fhrScriptName "FHR.config"; :put [/system script find where name=$fhrScriptName]',
    ':local fhrScheduleName "FHR.auto"; :put [/system scheduler find where name=$fhrScheduleName]',
    '/system script print where name="FHR.config"',
    '# Example of what not to use: find where name=$name',
    r':put "Never use find where name=\$name"',
])
def test_property_shadow_guard_accepts_safe_queries(code):
    assert not check.query_shadow_issues(code)

def test_computed_name_inside_install_loop_is_checked():
    code = (ROOT / 'tests/fixtures/ambiguous-script-lookup.rsc.txt').read_text(encoding='utf-8')
    assert len(check.query_shadow_issues(code)) == 1

def test_all_new_native_sources_and_controller_are_free_of_shadow_queries():
    files=list((ROOT/'routeros').glob('*.rsc'))+[ROOT/'FHR-install-all.rsc']
    for path in files:
        assert not check.query_shadow_issues(path.read_text(encoding='utf-8')),path.name

def test_installer_rechecks_exact_names_before_writes():
    source=(ROOT/'routeros/FHR-install.rsc').read_text(encoding='utf-8')
    assert 'get $fhrScriptId name] != $fhrScriptName' in source
    assert 'get $fhrScheduleId name] != $fhrScheduleName' in source
    assert 'Script ownership changed during install' in source
    assert '/system script set $fhrScriptId source=' in source
    assert '/system script remove' not in source
    assert source.index('Unmanaged scheduler uses') < source.index('/system scheduler disable')
    assert source.index('Unmanaged script already uses name') < source.index('/system script add')

def test_scheduler_operates_on_verified_ids_only():
    source=(ROOT/'routeros/FHR-commands.rsc').read_text(encoding='utf-8')
    block=source.split(':global FHRSchedule do={',1)[1].split(':global FHRDispatch do={',1)[0]
    assert 'get $fhrScheduleId name] != $fhrScheduleName' in block
    assert 'get $fhrScheduleId comment] != "FHR native v1"' in block
    assert '/system scheduler enable $fhrScheduleId' in block
    assert '/system scheduler disable $fhrScheduleId' in block
    assert 'Duplicate' in block or 'duplicate' in block

def test_uninstaller_checks_exact_schedule_name_and_owner():
    source=(ROOT/'routeros/FHR-uninstall.rsc').read_text(encoding='utf-8')
    assert 'get $fhrScheduleId name] = $fhrScheduleName' in source
    assert 'get $fhrScheduleId comment] = "FHR native v1"' in source
    assert 'name=$name' not in source

def test_saved_settings_are_not_purged_by_installer():
    installer=(ROOT/'routeros/FHR-install.rsc').read_text(encoding='utf-8')
    assert 'FHR.purge' not in installer
    assert 'FHR.restore' not in installer
    assert '/file remove' not in installer
    load=(ROOT/'routeros/FHR-load.rsc').read_text(encoding='utf-8')
    assert '$FHRLoadSettings' in load
    storage=(ROOT/'routeros/FHR-storage.rsc').read_text(encoding='utf-8')
    assert 'if ($k != "version")' in storage

def test_native_selftest_includes_exact_lookup_regression_checks():
    source=(ROOT/'routeros/FHR-selftest.rsc').read_text(encoding='utf-8')
    for label in ['exact script lookup count','exact script lookup identity',
                  'missing script lookup stays empty','missing scheduler lookup stays empty']:
        assert label in source
    assert len(re.findall(r'^\s*\$FHRAssert\b',source,re.M))==47

def test_release_identity_matches_the_operator_and_network_interfaces():
    for path, marker in {
        'routeros/FHR-config.rsc': '"version"="1.0.0";',
        'routeros/FHR-network.rsc': 'User-Agent:FastlyHosts-RouterOS/1.0.0"',
        'routeros/FHR-help.rsc': 'Fastly Hosts RouterOS 1.0.0 (',
        'routeros/FHR-install.rsc': 'INSTALLED 1.0.0.',
        'FHR-install-all.rsc': 'INSTALLED 1.0.0.',
    }.items():
        assert marker in (ROOT / path).read_text(encoding='utf-8'), path
