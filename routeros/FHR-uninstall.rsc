
/system script run FHR.purge
:foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
    :foreach fhrScheduleId in=[/system scheduler find where name=$fhrScheduleName] do={
        :if (([/system scheduler get $fhrScheduleId name] = $fhrScheduleName) && ([/system scheduler get $fhrScheduleId comment] = "FHR native v1")) do={/system scheduler remove $fhrScheduleId}
    }
}
:foreach id in=[/system script find where comment="FHR native v1"] do={/system script remove $id}
:put "FHR native scripts removed. Uploaded source files were retained."
