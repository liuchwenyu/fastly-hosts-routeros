# Managed exact A records only. No changes to DNS servers, AAAA, NAT, mangle or routes.
:global FHROwned do={:return ([:pick [:tostr $1] 0 9] = "FHR:auto:")}
:global FHRLegacy do={
    :local c [:tostr $1]
    :return (([:pick $c 0 15] = "FastlyROS:auto:") || ($c = "Fastly-Pilot-Raw") || ($c = "Fastly-Pilot-raw"))
}
:global FHRSnapshot do={
    :local out [:toarray ""]
    :foreach id in=$1 do={
        :set ($out->[:len $out]) {"name"=[/ip dns static get $id name];"address"=[:tostr [/ip dns static get $id address]];"ttl"=[:tostr [/ip dns static get $id ttl]];"comment"=[/ip dns static get $id comment];"disabled"=[/ip dns static get $id disabled]}
    }
    :return $out
}
:global FHRRestoreSnapshot do={
    :global FHROwned; :global FHRLegacy; :global FHRHostValid
    :local domains $1; :local records $2
    :foreach fhrHostName in=$domains do={
        :if (![$FHRHostValid $fhrHostName]) do={:error "unsafe journal hostname"}
        :foreach id in=[/ip dns static find where name=$fhrHostName and type="A"] do={
            :local c [/ip dns static get $id comment]
            :if ([$FHROwned $c]) do={/ip dns static remove $id}
        }
    }
    :foreach r in=$records do={
        :local h [:tostr ($r->"name")]; :local c [:tostr ($r->"comment")]
        :if ((![$FHRHostValid $h]) || (!([$FHROwned $c] || [$FHRLegacy $c]))) do={:error "journal contains an unmanaged record"}
        :local included false; :foreach domain in=$domains do={:if ($h = $domain) do={:set included true}}
        :if (!$included) do={:error "journal record outside transaction scope"}
        :local matches [/ip dns static find where name=$h and type="A" and comment=$c]
        :if ([:len $matches] > 0) do={
            /ip dns static set $matches address=($r->"address") ttl=[:totime ($r->"ttl")] disabled=($r->"disabled")
        } else={
            /ip dns static add name=$h type=A address=($r->"address") ttl=[:totime ($r->"ttl")] comment=$c disabled=($r->"disabled") match-subdomain=no
        }
    }
    /ip dns cache flush
}
:global FHRRecover do={
    :global FHRReadJSON; :global FHRWriteJSON; :global FHRDeleteState; :global FHRRestoreSnapshot
    :local tx [$FHRReadJSON "transaction"]
    :if ([:len $tx] > 0) do={
        :put "RECOVERY: restoring the interrupted DNS transaction"
        $FHRRestoreSnapshot ($tx->"domains") ($tx->"before")
        :local key [:tostr ($tx->"key")]
        :if ($key != "") do={
            :if ([:len ($tx->"oldCurrent")] > 0) do={$FHRWriteJSON ("current-" . $key) ($tx->"oldCurrent")} else={$FHRDeleteState ("current-" . $key)}
            :if ([:len ($tx->"oldPrevious")] > 0) do={$FHRWriteJSON ("previous-" . $key) ($tx->"oldPrevious")} else={$FHRDeleteState ("previous-" . $key)}
        }
        $FHRDeleteState "transaction"
    }
}
:global FHRPreflight do={
    :global FHRProbe; :global FHRHTTP; :global FHRHeader; :global FHRPop
    :global FHRAllowed; :global FHRSame24; :global FHRURL
    :local svc $1; :local row $2; :local bench $3; :local region $4
    :local primary [$FHRProbe $svc ($row->"ip") false]
    :if ((($primary->"ok") != true) || (![$FHRAllowed ($primary->"pop") $region])) do={:return {"ok"=false}}
    :if ((($svc->"mode") = "via") && (($primary->"pop") != ($row->"donorPOP"))) do={:return {"ok"=false}}
    :foreach fhrHostName,suffix in=($svc->"hosts") do={
        :local url ("https://" . $fhrHostName . ($svc->"paths"->$fhrHostName))
        :if (([:len $bench] > 0) && (($bench->"host") = $fhrHostName)) do={:set url ($bench->"url")}
        :local r [$FHRHTTP ({"url"=$url;"ip"=[$FHRSame24 ($row->"ip") $suffix];"method"="head";"seconds"=10})]
        :local code ($r->"code")
        # Generic API roots may legitimately return 403/404/405. A received HTTP
        # status still proves TLS passed; the profile's content probe is separate.
        :if (($code < 200) || ($code >= 500)) do={:return {"ok"=false;"host"=$fhrHostName;"reason"="alias TLS/HTTP"}}
        :if (([:len $bench] > 0) && (($bench->"host") = $fhrHostName) && (($code < 200) || ($code >= 300))) do={:return {"ok"=false;"host"=$fhrHostName;"reason"="benchmark alias invalid"}}
        :local pop [$FHRPop [$FHRHeader ($r->"http-headers") "x-served-by"]]
        :if (($pop != "?") && (![$FHRAllowed $pop $region])) do={:return {"ok"=false;"host"=$fhrHostName;"reason"="alias POP excluded or outside region"}}
    }
    :return {"ok"=true;"pop"=($primary->"pop")}
}
:global FHRCommit do={
    :global FHRConfig; :global FHRSame24; :global FHROwned; :global FHRLegacy
    :global FHRSnapshot; :global FHRReadJSON; :global FHRWriteJSON; :global FHRDeleteState; :global FHRRestoreSnapshot
    :local svc $1; :local chosen $2
    :local key ($svc->"key"); :local domains [:toarray ""]; :local oldIds [:toarray ""]
    :local baseline [$FHRReadJSON "baseline"]; :local changed false
    :foreach fhrHostName,suffix in=($svc->"hosts") do={
        :set ($domains->[:len $domains]) $fhrHostName
        :local legacyIds [:toarray ""]; :local already false
        :foreach rule in=[/ip dns static print as-value where disabled=no] do={
            :local typ [:tostr ($rule->"type")]
            :if (($typ = "A") || ($typ = "FWD") || ($typ = "CNAME") || ($typ = "NXDOMAIN")) do={
                :local re [:tostr ($rule->"regexp")]
                :if (($re != "") && ($fhrHostName ~ $re)) do={:error ("unmanaged DNS regexp matches " . $fhrHostName . "; not overwritten")}
                :if (([:tostr ($rule->"name")] = $fhrHostName) && ($typ != "A")) do={:error ("existing non-A static rule owns " . $fhrHostName)}
            }
        }
        :foreach id in=[/ip dns static find where name=$fhrHostName and type="A"] do={
            :local c [/ip dns static get $id comment]
            :if ([$FHROwned $c]) do={
                :set ($oldIds->[:len $oldIds]) $id
                :if (([:tostr [/ip dns static get $id address]] = [$FHRSame24 ($chosen->"ip") $suffix]) && ([/ip dns static get $id disabled] = false)) do={:set already true}
            } else={
                :if ((($FHRConfig->"adoptLegacy") = true) && [$FHRLegacy $c]) do={:set ($oldIds->[:len $oldIds]) $id; :set ($legacyIds->[:len $legacyIds]) $id; :set changed true} else={
                    :if ([/ip dns static get $id disabled] = false) do={:error ("unmanaged static A record for " . $fhrHostName . "; not overwritten")}
                }
            }
        }
        :if (!$already) do={:set changed true}
        :if ([:typeof ($baseline->$fhrHostName)] ~ "^(nil|nothing)\$") do={:set ($baseline->$fhrHostName) [$FHRSnapshot $legacyIds]}
    }
    :if (!$changed) do={
        :put ("KEPT DNS " . $key . " -> " . ($chosen->"ip") . " POP=" . ($chosen->"pop"))
        $FHRWriteJSON ("current-" . $key) ({"ip"=($chosen->"ip");"pop"=($chosen->"pop");"at"=([:tonsec [:timestamp]] / 1000000000);"hosts"=($svc->"hosts")})
        :return false
    }
    :local before [$FHRSnapshot $oldIds]
    :local oldCurrent [$FHRReadJSON ("current-" . $key)]
    :local oldPrevious [$FHRReadJSON ("previous-" . $key)]
    $FHRWriteJSON "baseline" $baseline
    $FHRWriteJSON "transaction" ({"domains"=$domains;"before"=$before;"key"=$key;"oldCurrent"=$oldCurrent;"oldPrevious"=$oldPrevious})
    :local created [:toarray ""]; :local errorText ""
    :onerror e in={
        :foreach fhrHostName,suffix in=($svc->"hosts") do={
            :local ip [$FHRSame24 ($chosen->"ip") $suffix]
            :local id [/ip dns static add name=$fhrHostName type=A address=$ip ttl=[:totime ($FHRConfig->"dnsTTL")] disabled=yes match-subdomain=no comment=("FHR:auto:" . $key . ":" . $fhrHostName)]
            :set ($created->[:len $created]) $id
        }
        :foreach id in=$oldIds do={/ip dns static disable $id}
        :foreach id in=$created do={/ip dns static enable $id}
        :foreach id in=$created do={:if ([/ip dns static get $id disabled] = true) do={:error "DNS activation verification failed"}}
        :foreach id in=$oldIds do={/ip dns static remove $id}
        $FHRWriteJSON ("previous-" . $key) ({"rows"=$before;"current"=$oldCurrent})
        $FHRWriteJSON ("current-" . $key) ({"ip"=($chosen->"ip");"pop"=($chosen->"pop");"at"=([:tonsec [:timestamp]] / 1000000000);"hosts"=($svc->"hosts")})
        $FHRDeleteState "transaction"
    } do={:set errorText [:tostr $e]}
    :if ($errorText != "") do={
        $FHRRestoreSnapshot $domains $before
        :if ([:len $oldCurrent] > 0) do={$FHRWriteJSON ("current-" . $key) $oldCurrent} else={$FHRDeleteState ("current-" . $key)}
        :if ([:len $oldPrevious] > 0) do={$FHRWriteJSON ("previous-" . $key) $oldPrevious} else={$FHRDeleteState ("previous-" . $key)}
        $FHRDeleteState "transaction"
        :error ("DNS transaction rolled back: " . $errorText)
    }
    /ip dns cache flush
    :put ("APPLIED " . $key . " -> " . ($chosen->"ip") . " POP=" . ($chosen->"pop") . " aliases=" . [:len $domains])
    :log info ("FHR applied " . $key . " " . ($chosen->"ip") . " " . ($chosen->"pop"))
    :return true
}
:global FHRRestore do={
    :global FHRProfiles; :global FHRReadJSON; :global FHRDeleteState; :global FHRWriteJSON; :global FHRRestoreSnapshot
    :local service [:tostr $1]; :local baseline [$FHRReadJSON "baseline"]
    :local domains [:toarray ""]; :local records [:toarray ""]; :local keep [:toarray ""]
    :foreach fhrHostName,rows in=$baseline do={
        :local include ($service = "")
        :if ($service != "") do={:if (!([:typeof ($FHRProfiles->$service->"hosts"->$fhrHostName)] ~ "^(nil|nothing)\$")) do={:set include true}}
        :if ($include) do={:set ($domains->[:len $domains]) $fhrHostName; :foreach row in=$rows do={:set ($records->[:len $records]) $row}} else={:set ($keep->$fhrHostName) $rows}
    }
    # Also remove managed entries after a lost baseline; never remove foreign records.
    :foreach r in=[/ip dns static print as-value where type="A"] do={
        :local c [:tostr ($r->"comment")]
        :if (([:pick $c 0 9] = "FHR:auto:") && (($service = "") || ([:pick $c 0 (10 + [:len $service])] = ("FHR:auto:" . $service . ":")))) do={
            :local fhrHostName [:tostr ($r->"name")]; :local seen false
            :foreach d in=$domains do={:if ($d = $fhrHostName) do={:set seen true}}
            :if (!$seen) do={:set ($domains->[:len $domains]) $fhrHostName}
        }
    }
    $FHRRestoreSnapshot $domains $records
    $FHRWriteJSON "baseline" $keep
    :foreach key,svc in=$FHRProfiles do={:if (($service = "") || ($service = $key)) do={$FHRDeleteState ("current-" . $key); $FHRDeleteState ("previous-" . $key)}}
    :put ("RESTORED " . [:len $domains] . " exact DNS names")
}
