# DISPOSABLE CHR ONLY. Upload chr-integration.rsc as integration.rsc first.
# The real scheduler runs all 20 integration assertions with declared policies.
/system script add name=LAB.integration policy=ftp,read,write,policy,test,sensitive source={
    /import file-name=integration.rsc
    :global FHRLabCount
    :if ($FHRLabCount != 20) do={:error "integration assertions incomplete"}
    :log info ("LAB SCHEDULED INTEGRATION PASS: " . $FHRLabCount . " checks; network replies are fixtures")
}
/system scheduler add name=LAB.integration interval=1s start-time=00:00:00 policy=ftp,read,write,policy,test,sensitive on-event={
    /system scheduler disable [find where name="LAB.integration"]
    /system script run LAB.integration
}
:put "LAB: scheduled integration armed"
