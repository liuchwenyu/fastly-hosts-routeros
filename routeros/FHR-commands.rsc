:global FHRValidateConfig do={
    :global FHRConfig; :global FHRHostValid; :global FHRIPNum
    :local bounds {"parallel"={1;32};"rounds"={1;9};"shortlist"={1;64};"sampleBytes"={262144;33554432};"sampleSeconds"={3;120};"probeSeconds"={2;30};"smoothFloorBps"={1;1000000000};"smoothPercent"={1;100};"stickyPercent"={0;100};"cacheSeconds"={60;604800};"cacheStaleSeconds"={60;2592000};"maxTextBytes"={65536;4194304};"maxBlocks"={256;65536};"healthFailures"={1;20};"nearMarginMs"={0;1000}}
    :foreach k,limits in=$bounds do={
        :local value [:tonum ($FHRConfig->$k)]
        :if ([:typeof $value] = "nil") do={:error ("configuration " . $k . " must be an integer")}
        :if (($value < ($limits->0)) || ($value > ($limits->1))) do={:error ("configuration out of range: " . $k)}
        :set ($FHRConfig->$k) $value
    }
    :foreach k in={"adoptLegacy";"allowLatencyFallback";"healthFailOpen";"verbose"} do={:if ([:typeof ($FHRConfig->$k)] != "bool") do={:error ("configuration " . $k . " must be true or false")}}
    :local src [$FHRIPNum ($FHRConfig->"sourceAddress")]
    :local ttl [:totime ($FHRConfig->"dnsTTL")]
    :if (($ttl < 1m) || ($ttl > 1d)) do={:error "dnsTTL must be between 1m and 1d"}
    :local re [:tostr ($FHRConfig->"excluded")]
    :if (!($re ~ "^[|]([A-Z]{3}[|])*\$")) do={:error "excluded must be a pipe-delimited set, e.g. |SIN|QPG|"}
    :if ((($FHRConfig->"latencyProbe") != "tcp") && (($FHRConfig->"latencyProbe") != "head")) do={:error "latencyProbe must be tcp or head"}
}
:global FHRAddCustom do={
    :global FHRProfiles; :global FHRTrim; :global FHRHostValid; :global FHRURL
    :global FHRRanges; :global FHRResolveAll; :global FHRInRanges; :global FHRIPNum
    :global FHRHTTP; :global FHRSaveSettings
    :local host [:convert transform=lc [$FHRTrim $1]]; :local testURL [:tostr $2]
    :if ([:pick $host 0 8] = "https://") do={:local u [$FHRURL $host]; :set host ($u->"host")}
    :if (![$FHRHostValid $host]) do={:error "invalid custom DNS hostname"}
    :foreach key,svc in=$FHRProfiles do={:if (!([:typeof ($svc->"hosts"->$host)] ~ "^(nil|nothing)\$")) do={:error "hostname is already in a profile"}}
    :local ranges [$FHRRanges]; :local counts [:toarray ""]; :local bestCount 0; :local suffix -1; :local original ""
    :foreach ip in=[$FHRResolveAll $host] do={
        :if ([$FHRInRanges $ip $ranges]) do={
            :local s [:tostr ([$FHRIPNum $ip] % 256)]; :local count [:tonum ($counts->$s)]
            :if ([:typeof $count] = "nil") do={:set count 0}
            :set count ($count + 1); :set ($counts->$s) $count
            :if ($count > $bestCount) do={:set bestCount $count; :set suffix [:tonum $s]; :set original $ip}
        }
    }
    :if ($suffix < 0) do={:error "current A answers are outside Fastly's public IPv4 ranges"}
    :local r [$FHRHTTP ({"url"=("https://" . $host . "/");"ip"=$original;"method"="head"})]
    :if ((($r->"code") < 200) || (($r->"code") >= 500)) do={:error "custom hostname failed TLS/HTTP validation"}
    :if ($testURL != "") do={
        :local parsed [$FHRURL $testURL]
        :if (($parsed->"host") != $host) do={:error "test URL must use the same hostname as the custom domain"}
    }
    :local key ("custom." . $host); :local hosts [:toarray ""]; :local paths [:toarray ""]
    :set ($hosts->$host) $suffix; :set ($paths->$host) "/"
    :set ($FHRProfiles->$key) {"key"=$key;"enabled"=true;"mode"="custom";"probeHost"=$host;"probePath"="/";"suffix"=$suffix;"anyStatus"=true;"popHost"="";"testURL"=$testURL;"hosts"=$hosts;"paths"=$paths}
    $FHRSaveSettings
    :put ("ADDED " . $key . " suffix=." . $suffix . " measured=" . ($testURL != ""))
}
:global FHRList do={
    :global FHRProfiles; :global FHRCacheRead
    :local only [:tostr $1]; :local grouped [:toarray ""]
    :foreach key,svc in=$FHRProfiles do={
        :if (($only = "") || ($only = $key)) do={
            :if (($svc->"mode") = "via") do={:put ($key . ": borrows " . ($svc->"via") . " ranking after its own TLS/POP verification")} else={
                :local cache [$FHRCacheRead $key]
                :foreach row in=($cache->"rows") do={
                    :local pop ($row->"pop"); :local group ($grouped->$pop)
                    :if ([:typeof $group] != "array") do={:set group {"pop"=$pop;"counts"=[:toarray ""];"us"=9223372036854775807;"kind"="head"}}
                    :local count [:tonum ($group->"counts"->$key)]; :if ([:typeof $count] = "nil") do={:set count 0}
                    :set ($group->"counts"->$key) ($count + 1)
                    :if (($row->"latencyUs") < ($group->"us")) do={:set ($group->"us") ($row->"latencyUs"); :set ($group->"kind") ($row->"latencyKind")}
                    :set ($grouped->$pop) $group
                }
            }
        }
    }
    :local ordered [:toarray ""]
    :foreach pop,group in=$grouped do={
        :local next [:toarray ""]; :local added false
        :foreach old in=$ordered do={
            :if ((!$added) && (($group->"us") < ($old->"us"))) do={:set ($next->[:len $next]) $group; :set added true}
            :set ($next->[:len $next]) $old
        }
        :if (!$added) do={:set ($next->[:len $next]) $group}
        :set ordered $next
    }
    :foreach group in=$ordered do={
        :local line ("POP " . ($group->"pop") . " timingUs=" . ($group->"us") . " timingKind=" . ($group->"kind"))
        :foreach key,count in=($group->"counts") do={:set line ($line . " " . $key . "=" . $count)}
        :put $line
    }
}
:global FHRStatus do={
    :global FHRConfig; :global FHRProfiles; :global FHRReadJSON
    :put ("FHR " . ($FHRConfig->"version") . " excluded=" . ($FHRConfig->"excluded") . " default-region=" . ($FHRConfig->"region"))
    :foreach key,svc in=$FHRProfiles do={
        :local current [$FHRReadJSON ("current-" . $key)]
        :put ($key . " enabled=" . ($svc->"enabled") . " selected=" . [:tostr ($current->"ip")] . " last-verified-POP=" . [:tostr ($current->"pop")])
    }
    /ip dns static print detail where comment~"^FHR:auto:"
    /system scheduler print where name~"^FHR[.]"
}
:global FHRSchedule do={
    :local fhrScheduleEnabled $1
    :foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
        :local fhrScheduleIds [/system scheduler find where name=$fhrScheduleName]
        :if ([:len $fhrScheduleIds] > 1) do={:error ("duplicate exact scheduler name: " . $fhrScheduleName)}
        :foreach fhrScheduleId in=$fhrScheduleIds do={
            :if ([/system scheduler get $fhrScheduleId name] != $fhrScheduleName) do={:error "scheduler lookup returned a different name"}
            :if ([/system scheduler get $fhrScheduleId comment] != "FHR native v1") do={:error ("unmanaged scheduler uses " . $fhrScheduleName)}
        }
    }
    :if ($fhrScheduleEnabled = true) do={
        # Verify file access with declared runtime permissions, not the interactive user.
        /system script run FHR.selftest use-script-permissions
        :if ([:len [/system scheduler find where name="FHR.auto"]] = 0) do={/system scheduler add name="FHR.auto" interval=6h start-time=00:00:00 disabled=yes policy=ftp,read,write,policy,test,sensitive on-event="/system script run FHR.apply" comment="FHR native v1"}
        :if ([:len [/system scheduler find where name="FHR.health"]] = 0) do={/system scheduler add name="FHR.health" interval=15m start-time=00:02:00 disabled=yes policy=ftp,read,write,policy,test,sensitive on-event="/system script run FHR.health" comment="FHR native v1"}
        :if ([:len [/system scheduler find where name="FHR.boot"]] = 0) do={/system scheduler add name="FHR.boot" interval=0s start-time=startup disabled=yes policy=ftp,read,write,policy,test,sensitive on-event=":delay 30s; /system script run FHR.health" comment="FHR native v1"}
        :foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
            :foreach fhrScheduleId in=[/system scheduler find where name=$fhrScheduleName] do={
                :if (([/system scheduler get $fhrScheduleId name] != $fhrScheduleName) || ([/system scheduler get $fhrScheduleId comment] != "FHR native v1")) do={:error "scheduler ownership changed"}
                /system scheduler set $fhrScheduleId policy=ftp,read,write,policy,test,sensitive
                /system scheduler enable $fhrScheduleId
            }
        }
        :put "SCHEDULE ENABLED: apply every 6h, health every 15m, boot health check"
    } else={
        :foreach fhrScheduleName in={"FHR.auto";"FHR.health";"FHR.boot"} do={
            :foreach fhrScheduleId in=[/system scheduler find where name=$fhrScheduleName] do={
                :if (([/system scheduler get $fhrScheduleId name] != $fhrScheduleName) || ([/system scheduler get $fhrScheduleId comment] != "FHR native v1")) do={:error "scheduler ownership changed"}
                /system scheduler disable $fhrScheduleId
            }
        }
        :put "SCHEDULE DISABLED"
    }
}
:global FHRDispatch do={
    :global FHRConfig; :global FHRProfiles; :global FHRRunServices; :global FHRRegionCode
    :global FHRStatus; :global FHRList; :global FHRHealth; :global FHRRestore; :global FHRSchedule
    :global FHRAddCustom; :global FHRSaveSettings; :global FHRReadJSON; :global FHRDeleteState
    :global FHRPreflight; :global FHRCommit; :global FHRValidateConfig; :global FHRText
    :local request $1; :local action [:tostr ($request->"action")]; :local service [:tostr ($request->"service")]
    :if (($action = "apply") || ($action = "test") || ($action = "scan") || ($action = "region") || ($action = "switch")) do={
        :local region [:tostr ($request->"region")]
        :if ($region = "") do={:set region ($FHRConfig->"region")}
        :set region [$FHRRegionCode $region]
        :if (($region != "") && ([:typeof [:find ($FHRConfig->"excluded") ("|" . $region . "|")]] != "nil")) do={:error "requested POP is explicitly excluded"}
        :if ((($action = "region") || ($action = "switch")) && ($region = "")) do={:error "region/switch requires a POP code"}
        :local opts {"service"=$service;"region"=$region;"apply"=(($action != "test") && ($action != "scan"));"scanOnly"=($action = "scan");"refresh"=(($action = "scan") || ($action = "region") || (($request->"refresh") = true));"cacheOnly"=($action = "switch");"full"=(($request->"full") = true)}
        :return [$FHRRunServices $opts]
    }
    :if ($action = "status") do={$FHRStatus; :return true}
    :if ($action = "list") do={$FHRList $service; :return true}
    :if ($action = "health") do={$FHRHealth; :return true}
    :if ($action = "enable-schedule") do={$FHRSchedule true; :return true}
    :if ($action = "disable-schedule") do={$FHRSchedule false; :return true}
    :if ($action = "restore") do={$FHRSchedule false; $FHRRestore $service; :return true}
    :if ($action = "add") do={$FHRAddCustom ($request->"domain") ($request->"url"); :return true}
    :if (($action = "enable") || ($action = "disable") || ($action = "remove")) do={
        :if ([:typeof ($FHRProfiles->$service)] ~ "^(nil|nothing)\$") do={:error "unknown service"}
        :if ($action = "remove") do={
            :if ([:pick $service 0 7] != "custom.") do={:error "built-in profiles can be disabled, not removed"}
            $FHRRestore $service
            :local keep [:toarray ""]; :foreach k,v in=$FHRProfiles do={:if ($k != $service) do={:set ($keep->$k) $v}}
            :set FHRProfiles $keep
        } else={
            :set ($FHRProfiles->$service->"enabled") ($action = "enable")
            :if ($action = "disable") do={$FHRRestore $service}
        }
        $FHRSaveSettings; :return true
    }
    :if ($action = "set-test-url") do={
        :global FHRURL
        :if ([:typeof ($FHRProfiles->$service)] ~ "^(nil|nothing)\$") do={:error "unknown service"}
        :local u [:tostr ($request->"url")]
        :if ($u != "") do={
            :local p [$FHRURL $u]
            :local expected ($FHRProfiles->$service->"probeHost")
            :if ($service = "twitch") do={:set expected "assets.twitch.tv"}
            :if (($p->"host") != $expected) do={:error "test URL hostname does not match profile"}
        }
        :if (($service = "github") || ($service = "x")) do={:error "GitHub/X use the release adapter; configure releaseRepos instead"}
        :set ($FHRProfiles->$service->"testURL") $u; $FHRSaveSettings; :return true
    }
    :if ($action = "set") do={
        :local property [:tostr ($request->"property")]
        :if (([:typeof ($FHRConfig->$property)] ~ "^(nil|nothing)\$") || ($property = "version") || ($property = "fallbackCIDRs")) do={:error "unknown or read-only property"}
        :local old $FHRConfig
        :set ($FHRConfig->$property) ($request->"value")
        :onerror e in={$FHRValidateConfig; $FHRSaveSettings} do={:set FHRConfig $old; :error $e}
        :return true
    }
    :if ($action = "rollback") do={
        :if ([:typeof ($FHRProfiles->$service)] ~ "^(nil|nothing)\$") do={:error "rollback requires service=github, x, twitch or a custom key"}
        :local prev [$FHRReadJSON ("previous-" . $service)]
        :local row ($prev->"current")
        :if ([:tostr ($row->"ip")] = "") do={$FHRRestore $service; :return true}
        :if ($service = "x") do={:set ($row->"donorPOP") ($row->"pop")}
        :local p [$FHRPreflight ($FHRProfiles->$service) $row [:toarray ""] ($FHRConfig->"region")]
        :if (($p->"ok") != true) do={:error "previous route is not valid under current POP policy; use restore for upstream DNS"}
        :set ($row->"pop") ($p->"pop"); :local changed [$FHRCommit ($FHRProfiles->$service) $row]; :return true
    }
    :if ($action = "purge") do={
        :global FHRDir
        $FHRSchedule false
        $FHRRestore ""
        :foreach f in=[/file print as-value] do={
            :local fhrStateFileName [:tostr ($f->"name")]
            :if (([:pick $fhrStateFileName 0 ([:len $FHRDir] + 1)] = ($FHRDir . "/")) && ($fhrStateFileName != ($FHRDir . "/run.lock")) && (($f->"type") != "directory")) do={/file remove ($f->".id")}
        }
        /system script run FHR.config
        :put "PURGED state and restored managed DNS; native program remains installed"
        :return true
    }
    :if ($action = "set-probe-path") do={
        :if ([:typeof ($FHRProfiles->$service)] ~ "^(nil|nothing)\$") do={:error "unknown service"}
        :local path [:tostr ($request->"value")]
        :if (([:pick $path 0 1] != "/") || ($path ~ "[\r\n]")) do={:error "probe path must be an absolute path without control characters"}
        :set ($FHRProfiles->$service->"probePath") $path
        :set ($FHRProfiles->$service->"paths"->($FHRProfiles->$service->"probeHost")) $path
        $FHRSaveSettings
        :return true
    }
    :if ($action = "check-update") do={
        :local data [:deserialize from=json options=json.no-string-conversion value=[$FHRText ({"url"="https://api.github.com/repos/AFAlimru/fastly-hosts-adjust/releases/latest";"headers"="Accept:application/vnd.github+json"})]]
        :put ("Upstream Python release: " . ($data->"tag_name") . "; port reference: v0.8.3; local port: " . ($FHRConfig->"version"))
        :put "No code downloaded or executed. Upgrade the native port by importing a reviewed replacement bundle."
        :return true
    }
    :error ("unknown action: " . $action . "; run /system script run FHR.help")
}
:global FHR do={
    # Public API. A per-filesystem lock serializes different RouterOS users too.
    :global FHRDir; :global FHRDispatch; :global FHRRecover; :global FHRValidateConfig
    :local request {"action"=$action;"service"=$service;"region"=$region;"domain"=$domain;"url"=$url;"property"=$property;"value"=$value;"refresh"=$refresh;"full"=$full}
    :local lock ($FHRDir . "/run.lock"); :local token [:tostr [:tonsec [:timestamp]]]
    :if ([:len [/file find where name=$lock]] > 0) do={
        :local stale false
        :onerror e in={
            :local old [:deserialize from=json options=json.no-string-conversion value=[/file get [/file find where name=$lock] contents]]
            :local now ([:tonsec [:timestamp]] / 1000000000)
            :local uptime ([:tonsec [/system resource get uptime]] / 1000000000)
            :local boot ($now - $uptime); :local delta ($boot - ($old->"boot"))
            :if (($delta > 300) || ($delta < -300) || (($now - ($old->"at")) > 14400)) do={:set stale true}
        } do={:error "unreadable FHR lock; inspect fhr-state/run.lock before removing it"}
        :if ($stale) do={/file remove [/file find where name=$lock]} else={:put "FHR BUSY: another run owns the lock; no changes made"; :return false}
    }
    :local now ([:tonsec [:timestamp]] / 1000000000)
    :local boot ($now - ([:tonsec [/system resource get uptime]] / 1000000000))
    :local lockData [:serialize to=json options=json.no-string-conversion value={"token"=$token;"at"=$now;"boot"=$boot}]
    /file add name=$lock type=file contents=$lockData
    :local result [:toarray ""]; :local failed ""
    :onerror e in={
        $FHRValidateConfig
        $FHRRecover
        :set result [$FHRDispatch $request]
    } do={:set failed [:tostr $e]}
    :onerror e in={
        :local current [:deserialize from=json options=json.no-string-conversion value=[/file get [/file find where name=$lock] contents]]
        :if (($current->"token") = $token) do={/file remove [/file find where name=$lock]}
    } do={}
    :if ($failed != "") do={:log error ("FHR: " . $failed); :error $failed}
    :return $result
}
