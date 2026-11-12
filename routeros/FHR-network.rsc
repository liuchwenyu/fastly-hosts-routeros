# Native RouterOS HTTPS and bounded probe workers.
:global FHRHTTP do={
    :global FHRConfig; :global FHRURL
    :local req $1; :local parsed [$FHRURL ($req->"url")]
    :local u ($parsed->"url"); :local ip [:tostr ($req->"ip")]
    :if (($FHRConfig->"vrf") != "") do={:set ip ($ip . "@" . ($FHRConfig->"vrf"))}
    :local method [:tostr ($req->"method")]; :if ($method = "") do={:set method "head"}
    :local output [:tostr ($req->"output")]; :if ($output = "") do={:set output "user-with-headers"}
    :local seconds [:tonum ($req->"seconds")]; :if ([:typeof $seconds] = "nil") do={:set seconds ($FHRConfig->"probeSeconds")}
    :local extra [:tostr ($req->"headers")]
    :local hdr "Accept-Encoding:identity,User-Agent:FastlyHosts-RouterOS/1.0.0"
    :if ($extra != "") do={:set hdr ($hdr . "," . $extra)}
    :local r [:toarray ""]; :local began [:timestamp]
    :onerror err,attrs in={
        :set r [/tool fetch url=$u address=$ip src-address=($FHRConfig->"sourceAddress") ip-type=ipv4 http-method=$method http-max-redirect-count=0 http-header-field=$hdr check-certificate=yes output=$output dst-path=[:tostr ($req->"file")] as-value idle-timeout=4s duration=[:totime ($seconds . "s")]]
        :set ($r->"requestOK") true
    } do={
        :if ([:typeof $attrs] = "array") do={:set r $attrs}
        :set ($r->"requestOK") false; :set ($r->"error") [:tostr $err]
    }
    :set ($r->"wallMs") ([:tonsec ([:timestamp] - $began)] / 1000000)
    :if ([:typeof ($r->"code")] ~ "^(nil|nothing)\$") do={:set ($r->"code") 0} else={:set ($r->"code") [:tonum ($r->"code")]}
    :if ([:typeof ($r->"http-headers")] ~ "^(nil|nothing)\$") do={:set ($r->"http-headers") [:toarray ""]}
    :return $r
}
:global FHRText do={
    # Metadata can exceed output=user's 64KB cap. Only metadata uses a scratch file.
    :global FHRHTTP; :global FHRConfig; :global FHRDir
    :local req $1; :local path ($FHRDir . "/metadata.tmp")
    :set ($req->"method") "get"; :set ($req->"output") "file"; :set ($req->"file") $path; :set ($req->"seconds") 20
    :if ([:len [/file find where name=$path]] > 0) do={/file remove [/file find where name=$path]}
    :local r [$FHRHTTP $req]; :local result ""; :local bad ""
    :onerror e in={
        :if ((($r->"requestOK") != true) || (($r->"status") != "finished") || (($r->"code") != 200)) do={:error "metadata HTTPS request failed"}
        :local id [/file find where name=$path]
        :local size [/file get $id size]
        :if (($size <= 0) || ($size > ($FHRConfig->"maxTextBytes"))) do={:error "metadata exceeds configured size bound"}
        :local offset 0
        :while ($offset < $size) do={
            :local part [/file read file=$path offset=$offset chunk-size=32768 as-value]
            :local data [:tostr ($part->"data")]
            :if ([:len $data] = 0) do={:error "empty metadata chunk"}
            :set result ($result . $data); :set offset ($offset + [:len $data])
        }
    } do={:set bad [:tostr $e]}
    :if ([:len [/file find where name=$path]] > 0) do={/file remove [/file find where name=$path]}
    :if ($bad != "") do={:error $bad}
    :return $result
}
:global FHRTCP do={
    # Short-lived native TCP probes. Never install Netwatch event scripts.
    :global FHRConfig
    :local ip [:tostr $1]; :local id ""; :local answer {"ok"=false;"us"=0;"typed"=false}
    :if (($FHRConfig->"vrf") != "") do={:set ip ($ip . "@" . ($FHRConfig->"vrf"))}
    :onerror e in={
        :set id [/tool netwatch add host=$ip type=tcp-conn port=443 interval=1h timeout=2s thr-tcp-conn-time=2s start-delay=0s startup-delay=0s disabled=yes comment="FHR:temporary-tcp" up-script="" down-script="" test-script=""]
        :if (($FHRConfig->"sourceAddress") != "0.0.0.0") do={/tool netwatch set $id src-address=($FHRConfig->"sourceAddress")}
        /tool netwatch enable $id
        :local deadline ([:timestamp] + 4s)
        :while (([/tool netwatch get $id done-tests] = 0) && ([:timestamp] < $deadline)) do={:delay 50ms}
        :if ([/tool netwatch get $id status] = "up") do={
            :set ($answer->"ok") true
            :local elapsed [/tool netwatch get $id tcp-connect-time]
            :if ([:typeof $elapsed] = "time") do={
                :set ($answer->"us") ([:tonsec $elapsed] / 1000); :set ($answer->"typed") true
            }
        }
    } do={}
    :if ($id != "") do={:onerror e in={/tool netwatch remove $id} do={}}
    :return $answer
}
:global FHRProbe do={
    :global FHRHTTP; :global FHRHeader; :global FHRPop; :global FHRSame24
    :global FHRAllowed; :global FHRConfig; :global FHRTCP
    :local svc $1; :local base [:tostr $2]; :local tcp $3
    :local ip [$FHRSame24 $base ($svc->"suffix")]
    :local u ("https://" . ($svc->"probeHost") . ($svc->"probePath"))
    :local r [$FHRHTTP ({"url"=$u;"ip"=$ip;"method"="head"})]
    :local code ($r->"code"); :local valid false
    :if ((($svc->"anyStatus") = true) && ($code >= 200) && ($code < 500)) do={:set valid true}
    :if ((($r->"requestOK") = true) && ($code >= 200) && ($code < 400)) do={:set valid true}
    :if (!$valid) do={:return {"ok"=false;"ip"=$ip;"reason"="TLS/HTTP";"code"=$code}}
    :local pop [$FHRPop [$FHRHeader ($r->"http-headers") "x-served-by"]]
    :if ([:tostr ($svc->"popHost")] != "") do={
        :local q [$FHRHTTP ({"url"=("https://" . ($svc->"popHost") . ($svc->"popPath"));"ip"=[$FHRSame24 $ip ($svc->"popSuffix")];"method"="head"})]
        :set pop [$FHRPop [$FHRHeader ($q->"http-headers") "x-served-by"]]
    }
    :if (![$FHRAllowed $pop ""]) do={:return {"ok"=false;"ip"=$ip;"pop"=$pop;"reason"="excluded-or-unknown-POP"}}
    :local us (($r->"wallMs") * 1000); :local kind "head"
    :if (($tcp = true) && (($FHRConfig->"latencyProbe") = "tcp")) do={
        :local t [$FHRTCP $ip]
        :if (($t->"ok") && ($t->"typed")) do={:set us ($t->"us"); :set kind "tcp"}
    }
    :return {"ok"=true;"ip"=$ip;"pop"=$pop;"headMs"=($r->"wallMs");"latencyUs"=$us;"latencyKind"=$kind;"code"=$code}
}
:global FHRParallel do={
    :global FHRConfig; :global FHRProbe
    :global FHRWork; :global FHRWorkResults; :global FHRWorkToken
    :local svc $1; :local ips $2; :local measure $3
    :local parallel ($FHRConfig->"parallel"); :local results [:toarray ""]
    :local active [:toarray ""]; :local next 0; :local done 0
    :set FHRWork [:toarray ""]; :set FHRWorkResults [:toarray ""]
    :set FHRWorkToken [:tostr [:tonsec [:timestamp]]]
    :local token $FHRWorkToken; :local fatal ""
    :onerror e in={
        :while (($next < [:len $ips]) || ([:len $active] > 0)) do={
            :while (($next < [:len $ips]) && ([:len $active] < $parallel)) do={
                :local slot [:tostr $next]
                :set ($FHRWork->$slot) {"svc"=$svc;"ip"=($ips->$next);"tcp"=$measure;"token"=$token}
                # Only a generated integer enters code. URLs and domains remain data.
                :local worker (":global FHRWork; :global FHRWorkResults; :global FHRWorkToken; :global FHRProbe; :local slot \"" . $slot . "\"; :local w (\$FHRWork->\$slot); :local r {\"ok\"=false}; :onerror e in={ :set r [\$FHRProbe (\$w->\"svc\") (\$w->\"ip\") (\$w->\"tcp\")] } do={ :set (\$r->\"reason\") [:tostr \$e] }; :if (\$FHRWorkToken = (\$w->\"token\")) do={ :set (\$r->\"done\") true; :set (\$FHRWorkResults->\$slot) \$r }")
                :local job [:execute script=$worker]
                :set ($active->$slot) {"id"=$job;"started"=[:timestamp]}
                :set next ($next + 1)
            }
            :local remaining [:toarray ""]
            :foreach slot,job in=$active do={
                :local result ($FHRWorkResults->$slot)
                :if (($result->"done") = true) do={
                    :if (($result->"ok") = true) do={
                        :set ($results->[:len $results]) $result
                        :if (($FHRConfig->"verbose") = true) do={:put ("VALID " . ($svc->"key") . " " . ($result->"ip") . " POP=" . ($result->"pop"))}
                    }
                    :set done ($done + 1)
                } else={
                    :if (([:timestamp] - ($job->"started")) > [:totime ((($FHRConfig->"probeSeconds") * 3 + 10) . "s")]) do={
                        :onerror err in={/system script job remove ($job->"id")} do={}
                        :set done ($done + 1)
                        :log warning ("FHR: probe worker timeout " . ($svc->"key") . " " . $slot)
                    } else={:set ($remaining->$slot) $job}
                }
            }
            :if (([:len $remaining] < [:len $active]) && (($done % 40) = 0)) do={:put ("DISCOVER " . ($svc->"key") . " " . $done . "/" . [:len $ips] . " nonSG=" . [:len $results])}
            :set active $remaining
            :if ([:len $active] > 0) do={:delay 100ms}
        }
    } do={:set fatal [:tostr $e]}
    :set FHRWorkToken ""
    :foreach slot,job in=$active do={:onerror e in={/system script job remove ($job->"id")} do={}}
    /tool netwatch remove [/tool netwatch find where comment="FHR:temporary-tcp"]
    :set FHRWork [:toarray ""]; :set FHRWorkResults [:toarray ""]
    :if ($fatal != "") do={:error $fatal}
    :return $results
}
:global FHRResolveAll do={
    :global FHRConfig
    :local fhrHostName [:tostr $1]; :local out [:toarray ""]; :local seen [:toarray ""]
    :onerror e in={
        :local ip ""
        :if (($FHRConfig->"resolver") = "") do={:set ip [:tostr [:resolve domain-name=$fhrHostName type=ipv4]]} else={:set ip [:tostr [:resolve domain-name=$fhrHostName server=($FHRConfig->"resolver") type=ipv4]]}
        :set ($out->[:len $out]) $ip; :set ($seen->$ip) true
    } do={}
    :foreach row in=[/ip dns cache all print as-value where name=$fhrHostName and type="A"] do={
        :local ip [:tostr ($row->"data")]
        :if (($ip != "") && ([:typeof ($seen->$ip)] ~ "^(nil|nothing)\$")) do={:set ($out->[:len $out]) $ip; :set ($seen->$ip) true}
    }
    :return $out
}
