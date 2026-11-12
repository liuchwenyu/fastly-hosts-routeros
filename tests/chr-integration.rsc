# ISOLATED CHR TEST ONLY: creates temporary lab DNS data and mocks network replies.
# This file is not embedded in the production installer.
/system script run FHR.load
:global FHRConfig; :global FHRProfiles; :global FHR
:global FHRHTTP; :global FHRProbe; :global FHREvaluate; :global FHRRanges; :global FHRResolveAll
:global FHRParallel; :global FHRReadJSON; :global FHRWriteJSON; :global FHRDeleteState
:global FHRSame24; :global FHRCommit; :global FHRRestore
:global FHRLabCount 0
:global FHRLabAssert do={:global FHRLabCount; :if ($1 != true) do={:error ("LAB FAILED: " . $2)}; :set FHRLabCount ($FHRLabCount + 1)}
:global FHRHTTP do={:return {"code"=200;"requestOK"=true;"status"="finished";"http-headers"={"x-served-by"="cache-lab-NRT"}}}
:global FHRProbe do={
    :global FHRSame24
    :local svc $1
    :return {"ok"=true;"ip"=[$FHRSame24 $2 ($svc->"suffix")];"pop"="NRT";"latencyUs"=10000;"latencyKind"="tcp";"headMs"=10;"code"=200}
}
:global FHRRanges do={:return {"151.101.0.0/16"}}
:global FHRResolveAll do={:return {"151.101.0.42"}}
:global FHREvaluate do={
    :global FHRSame24
    :local svc $1; :local ranked [:toarray ""]
    :set ($ranked->0) {"ip"=[$FHRSame24 "151.101.0.0" ($svc->"suffix")];"pop"="NRT";"smooth"=3;"valid"=3;"medianBps"=10000000;"latencyUs"=10000;"latencyKind"="tcp"}
    :return {"ranked"=$ranked;"bench"=[:toarray ""];"measured"=true;"found"=1}
}
:local workers [$FHRParallel ($FHRProfiles->"github") ({"151.101.0.133";"151.101.1.133";"151.101.2.133"}) false]
$FHRLabAssert ([:len $workers] = 3) "three native background workers return results"
$FHRLabAssert ([:len [/tool netwatch find where comment="FHR:temporary-tcp"]] = 0) "worker cleanup"
/ip dns static add name=untouched.example type=A address=192.0.2.8 comment="LAB:foreign"
/ip dns static add name=raw.githubusercontent.com type=AAAA address=2001:db8::1 comment="LAB:foreign"
$FHR action="add" domain="custom.example"
$FHRLabAssert (($FHRProfiles->"custom.custom.example"->"suffix") = 42) "custom suffix discovery"
:local report [$FHR action="apply"]
$FHRLabAssert ([:len $report] = 4) "four service results"
$FHRLabAssert ([:len [/ip dns static find where comment~"^FHR:auto:"]] = 9) "nine managed exact A records"
$FHRLabAssert ([:tostr [/ip dns static get [find where name="k.twitchcdn.net" and type=A] address]] = "151.101.0.167") "Twitch secondary suffix"
$FHRLabAssert ([:tostr [/ip dns static get [find where name="pbs.twimg.com" and type=A] address]] = "151.101.0.159") "X suffix"
$FHRLabAssert ([:len [/ip dns static find where comment="LAB:foreign"]] = 2) "foreign and AAAA preserved"
:local again [$FHR action="apply"]
$FHRLabAssert ([:len [/ip dns static find where comment~"^FHR:auto:"]] = 9) "repeat apply has no duplicates"
$FHRLabAssert ([:len [/file find where name="fhr-state/run.lock"]] = 0) "API lock released"
:global FHRLabOriginalWrite $FHRWriteJSON
:global FHRLabInject true
:global FHRWriteJSON do={
    :global FHRLabOriginalWrite; :global FHRLabInject
    :if (($1 = "previous-github") && $FHRLabInject) do={:set FHRLabInject false; :error "injected state failure after DNS activation"}
    :return [$FHRLabOriginalWrite $1 $2]
}
:local rejected false
:onerror e in={:local changed [$FHRCommit ($FHRProfiles->"github") ({"ip"="151.101.192.133";"pop"="NRT"})]} do={:set rejected true}
:set FHRWriteJSON $FHRLabOriginalWrite
$FHRLabAssert $rejected "injected post-activation failure propagated"
$FHRLabAssert ([:tostr [/ip dns static get [find where name="raw.githubusercontent.com" and type=A] address]] = "151.101.0.133") "failed commit restored old DNS"
:local current [$FHRReadJSON "current-github"]
$FHRLabAssert (($current->"ip") = "151.101.0.133") "failed commit restored current state"
$FHRLabAssert ([:len [$FHRReadJSON "transaction"]] = 0) "rollback journal cleared"
$FHR action="restore"
$FHRLabAssert ([:len [/ip dns static find where comment~"^FHR:auto:"]] = 0) "restore removes managed records"
$FHRLabAssert ([:len [/ip dns static find where comment="LAB:foreign"]] = 2) "restore preserves foreign records"
/ip dns static add name=raw.githubusercontent.com type=A address=192.0.2.9 comment="LAB:foreign"
:set rejected false
:onerror e in={:local changed [$FHRCommit ($FHRProfiles->"github") ({"ip"="151.101.192.133";"pop"="NRT"})]} do={:set rejected true}
$FHRLabAssert $rejected "foreign A ownership rejected"
$FHRLabAssert ([:tostr [/ip dns static get [find where name="raw.githubusercontent.com" and type=A] address]] = "192.0.2.9") "foreign A remains unchanged"
/ip dns static remove [find where comment="LAB:foreign"]
$FHR action="remove" service="custom.custom.example"
$FHR action="set" property="parallel" value=3
$FHR action="enable-schedule"
$FHRLabAssert ([:len [/system scheduler find where comment="FHR native v1" and disabled=no]] = 3) "three schedules enabled"
$FHR action="disable-schedule"
$FHRLabAssert ([:len [/system scheduler find where comment="FHR native v1" and disabled=yes]] = 3) "three schedules disabled"
:put ("CHR INTEGRATION PASS: " . $FHRLabCount . " checks; network replies were fixtures")
/system script run FHR.load
