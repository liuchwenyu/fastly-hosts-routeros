
# Upload all FHR-*.rsc files from routeros/ to the SAME WinBox Files directory.
# Default is Files root. For a folder upload, change this one prefix, e.g. "fhr/".
# Use distinct lookup variables for RouterOS name properties.
{
    :local prefix ""
    :local parts {"config";"core";"storage";"network";"benchmarks";"discovery";"dns";"engine";"commands";"load";"selftest";"apply";"test";"scan";"status";"health";"restore";"purge";"enable-schedule";"disable-schedule";"help";"doctor";"uninstall"}
    :local sources [:toarray ""]
    :put "FHR installer 1.0.0: checking sources and exact ownership before changes"
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
    :put "INSTALLED 1.0.0. No DNS switch was made by the installer."
    :put "New installation: run /system script run FHR.apply when ready to select DNS targets."
    :put "Existing installation: check FHR.doctor first. To resume automatic operation, run /system script run FHR.enable-schedule."
}
