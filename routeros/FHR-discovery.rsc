:global FHRRanges do={
    :global FHRHTTP; :global FHRConfig; :global FHRCIDR
    :local ranges [:toarray ""]
    :onerror e in={
        :local r [$FHRHTTP ({"url"="https://api.fastly.com/public-ip-list";"method"="get";"output"="user";"seconds"=15})]
        :if ((($r->"requestOK") != true) || (($r->"code") != 200)) do={:error "Fastly API request failed"}
        :local data [:deserialize from=json options=json.no-string-conversion value=($r->"data")]
        :foreach cidr in=($data->"addresses") do={:local checked [$FHRCIDR $cidr]; :set ranges ($ranges, [:tostr $cidr])}
    } do={:put ("Fastly API unavailable; using bundled official snapshot: " . $e)}
    :if ([:len $ranges] = 0) do={:set ranges ($FHRConfig->"fallbackCIDRs")}
    :return $ranges
}
:global FHRDiscover do={
    :global FHRConfig; :global FHRBlocks; :global FHRSame24; :global FHRInRanges
    :global FHRResolveAll; :global FHRParallel; :global FHRCacheRead; :global FHRCacheWrite
    :local svc $1; :local ranges $2; :local refresh $3; :local cacheOnly $4
    :local key ($svc->"key"); :local cache [$FHRCacheRead $key]
    :local age 999999999; :local rows ($cache->"rows")
    :if (!([:typeof ($cache->"at")] ~ "^(nil|nothing)\$")) do={:set age (([:tonsec [:timestamp]] / 1000000000) - [:tonum ($cache->"at")])}
    :local ips [:toarray ""]; :local seen [:toarray ""]; :local fromCache false
    :if (($refresh != true) && ([:len $rows] > 0) && ($age >= 0) && ($age <= ($FHRConfig->"cacheSeconds"))) do={:set fromCache true}
    :if ($cacheOnly = true) do={
        :if (([:len $rows] = 0) || ($age < 0) || ($age > ($FHRConfig->"cacheStaleSeconds"))) do={:error "no usable scan cache; run apply or region once"}
        :set fromCache true
    }
    :if ($fromCache) do={
        :foreach row in=$rows do={
            :local ip [:tostr ($row->"ip")]
            :if ([:typeof ($seen->$ip)] ~ "^(nil|nothing)\$") do={:set ($ips->[:len $ips]) $ip; :set ($seen->$ip) true}
        }
        :put ("CACHE " . $key . ": revalidating " . [:len $ips] . " candidates")
    } else={
        :local blocks [$FHRBlocks $ranges ($FHRConfig->"maxBlocks")]
        # Prioritization only changes order. No stride sampling and no silent cap.
        :foreach block in=($FHRConfig->"priorityBlocks") do={
            :local ip [$FHRSame24 $block ($svc->"suffix")]
            :if ([$FHRInRanges $ip $ranges]) do={:set ($ips->[:len $ips]) $ip; :set ($seen->$ip) true}
        }
        :foreach block in=$blocks do={
            :local ip [$FHRSame24 $block ($svc->"suffix")]
            :if (([:typeof ($seen->$ip)] ~ "^(nil|nothing)\$") && [$FHRInRanges $ip $ranges]) do={:set ($ips->[:len $ips]) $ip; :set ($seen->$ip) true}
        }
        :put ("FULL DISCOVERY " . $key . ": " . [:len $ips] . " service IPs from " . [:len $blocks] . " /24 blocks")
    }
    # The service's actual DNS can use dedicated ranges absent from the Fastly API.
    :foreach base in=[$FHRResolveAll ($svc->"probeHost")] do={
        :local ip [$FHRSame24 $base ($svc->"suffix")]
        :if ([:typeof ($seen->$ip)] ~ "^(nil|nothing)\$") do={:set ($ips->[:len $ips]) $ip; :set ($seen->$ip) true}
    }
    :local verified [$FHRParallel $svc $ips true]
    :if (([:len $verified] = 0) && $fromCache && ($cacheOnly != true)) do={
        # One bounded fallback to the full official candidate space, not recursion.
        :set ips [:toarray ""]; :set seen [:toarray ""]
        :foreach block in=[$FHRBlocks $ranges ($FHRConfig->"maxBlocks")] do={
            :local ip [$FHRSame24 $block ($svc->"suffix")]
            :if ([$FHRInRanges $ip $ranges]) do={:set ($ips->[:len $ips]) $ip}
        }
        :put ("CACHE " . $key . " exhausted; expanding to all service IPs")
        :set verified [$FHRParallel $svc $ips true]
        :set fromCache false
    }
    :if ([:len $verified] > 0) do={
        # Do not renew a cache's discovery age just because its survivors were rechecked.
        :if (!$fromCache) do={:onerror e in={$FHRCacheWrite $key $verified} do={:log warning ("FHR: cache save failed for " . $key . ": " . $e)}}
    }
    :put ("DISCOVERY COMPLETE " . $key . ": " . [:len $verified] . " eligible non-Singapore routes")
    :return $verified
}
:global FHRShortlist do={
    :global FHRConfig; :global FHRRank; :global FHRAllowed; :global FHRReadJSON
    :local svc $1; :local rows $2; :local region [:tostr $3]; :local full $4
    :local eligible [:toarray ""]; :local nearest 9223372036854775807
    :foreach row in=$rows do={
        :if ([$FHRAllowed ($row->"pop") $region]) do={
            :set ($eligible->[:len $eligible]) $row
            :if ((($row->"latencyKind") = "tcp") && (($row->"latencyUs") < $nearest)) do={:set nearest ($row->"latencyUs")}
        }
    }
    :local band [:toarray ""]
    :foreach row in=$eligible do={
        :if (($full = true) || ($region != "") || (($row->"latencyKind") != "tcp") || (($row->"latencyUs") <= ($nearest + ($FHRConfig->"nearMarginMs") * 1000))) do={:set ($band->[:len $band]) $row}
    }
    :local ranked [$FHRRank $band [:toarray ""]]
    :local out [:toarray ""]; :local seen [:toarray ""]
    :local current [$FHRReadJSON ("current-" . ($svc->"key"))]
    :foreach row in=$eligible do={
        :if (($row->"ip") = ($current->"ip")) do={:set ($out->[:len $out]) $row; :set ($seen->($row->"ip")) true}
    }
    :foreach row in=$ranked do={
        :if (([:len $out] < ($FHRConfig->"shortlist")) && ([:typeof ($seen->($row->"ip"))] ~ "^(nil|nothing)\$")) do={
            :set ($out->[:len $out]) $row; :set ($seen->($row->"ip")) true
        }
    }
    :return $out
}
:global FHRRegionCode do={
    :global FHRTrim
    :local text [:convert transform=uc [$FHRTrim $1]]
    :if (($text = "") || ($text = "AUTO")) do={:return ""}
    # Codes are unambiguous. Common city aliases are convenience mappings.
    :local aliases {"TOKYO"="NRT";"OSAKA"="ITM";"SEOUL"="ICN";"HONG KONG"="HKG";"SINGAPORE"="SIN";"TAIPEI"="TPE";"LOS ANGELES"="BUR";"LONDON"="LHR";"NEW YORK"="LGA";"DALLAS"="DFW";"CHENNAI"="MAA"}
    :if (!([:typeof ($aliases->$text)] ~ "^(nil|nothing)\$")) do={:set text ($aliases->$text)}
    :if (!($text ~ "^[A-Z]{3}\$")) do={:error "use a three-letter POP code, e.g. NRT, ITM or ICN"}
    :return $text
}
