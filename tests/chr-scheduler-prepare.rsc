# DISPOSABLE CHR ONLY. Prepare an existing installation before reimport.
# Creates fixture DNS/state under full interactive permissions, then launches
# a real scheduler without permission to read sensitive state. No Internet requests.
/system script run FHR.load
:global FHRProfiles; :global FHRCommit; :global FHRWriteJSON
$FHRCommit ($FHRProfiles->"github") ({"ip"="146.75.112.133";"pop"="NRT"})
$FHRCommit ($FHRProfiles->"twitch") ({"ip"="199.232.106.214";"pop"="NRT"})
$FHRCommit ($FHRProfiles->"x") ({"ip"="146.75.112.159";"pop"="NRT"})
/system script run FHR.enable-schedule
/system script run FHR.disable-schedule
/system script add name=LAB.health policy=ftp,read,write,policy,test source={
    /system script run FHR.load
    :global FHRPreflight do={:return {"ok"=true;"pop"="NRT"}}
    :global FHR
    $FHR action="health"
    :log info "LAB HEALTH PASS: real scheduler; network replies are fixtures"
}
/system scheduler add name=LAB.health interval=1s start-time=00:00:00 policy=ftp,read,write,policy,test on-event={
    /system scheduler disable [find where name="LAB.health"]
    /system script run LAB.health
}
:put "LAB: scheduler reproduction armed; inspect log after it fires"
