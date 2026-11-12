# Service-specific metadata adapters. All scoring and DNS writing are shared.
:global FHRGitHubAsset do={
    :global FHRConfig; :global FHRText; :global FHRURL
    :local selected [:toarray ""]
    :foreach repo in=($FHRConfig->"releaseRepos") do={
        :onerror e in={
            :if (!([:tostr $repo] ~ "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\$")) do={:error "invalid release repository"}
            :local body [$FHRText ({"url"=("https://api.github.com/repos/" . $repo . "/releases/latest");"headers"="Accept:application/vnd.github+json"})]
            :local data [:deserialize from=json options=json.no-string-conversion value=$body]
            :local largest 0; :local public ""
            :foreach asset in=($data->"assets") do={
                :local n [:tonum ($asset->"size")]
                :if (($n > $largest) && ([:tostr ($asset->"browser_download_url")] != "")) do={
                    :set largest $n; :set public [:tostr ($asset->"browser_download_url")]
                }
            }
            :if (($largest >= 262144) && ($public != "")) do={
                :local parsed [$FHRURL $public]
                :if (($parsed->"host") != "github.com") do={:error "unexpected release metadata host"}
                :set selected {"mode"="github";"public"=$public;"size"=$largest;"host"="release-assets.githubusercontent.com";"suffix"=133}
            }
        } do={:put ("METADATA github: " . $repo . " unavailable: " . $e)}
        :if ([:len $selected] > 0) do={:break}
    }
    :return $selected
}
:global FHRSignedURL do={
    :global FHRHTTP; :global FHRHeader; :global FHRURL
    :local u [:tostr $1]
    :for hop from=0 to=4 do={
        :local parsed [$FHRURL $u]
        :if (($parsed->"host") = "release-assets.githubusercontent.com") do={:return $u}
        :if (($parsed->"host") != "github.com") do={:error "unexpected release redirect host"}
        :local r [$FHRHTTP ({"url"=$u;"method"="head";"seconds"=15})]
        :local code ($r->"code")
        :if (!(($code = 301) || ($code = 302) || ($code = 303) || ($code = 307) || ($code = 308))) do={:error "GitHub did not return a release redirect"}
        :local next [$FHRHeader ($r->"http-headers") "location"]
        :if ([:pick $next 0 1] = "/") do={:set next ("https://github.com" . $next)}
        :local parsedNext [$FHRURL $next]
        :set u ($parsedNext->"url")
    }
    :error "too many release redirects"
}
:global FHRTwitchAsset do={
    :global FHRText; :global FHRSame24; :global FHRURL
    :local rows $1; :local html ""; :local tries 0
    :foreach row in=$rows do={
        :if (($html = "") && ($tries < 5)) do={
            :set tries ($tries + 1)
            :onerror e in={:set html [$FHRText ({"url"="https://www.twitch.tv/";"ip"=[$FHRSame24 ($row->"ip") 214]})]} do={}
        }
    }
    :if ($html = "") do={:onerror e in={:set html [$FHRText ({"url"="https://www.twitch.tv/"})]} do={}}
    :if ($html = "") do={:error "Twitch homepage unavailable"}
    :local prefix "https://assets.twitch.tv/assets/"; :local offset 0; :local first ""; :local preferred ""
    :while ($offset < [:len $html]) do={
        :local start [:find $html $prefix $offset]
        :if ([:typeof $start] = "nil") do={:break}
        :local end [:find $html ".js" $start]
        :if ([:typeof $end] = "nil") do={:break}
        :local candidate [:pick $html $start ($end + 3)]
        :if (([:len $candidate] < 2048) && (!($candidate ~ "[\r\n<>\"' ]"))) do={
            :local parsed [$FHRURL $candidate]
            :if (($parsed->"host") = "assets.twitch.tv") do={
                :if ($first = "") do={:set first $candidate}
                :if (([:typeof [:find $candidate "nomodulePolyfills"]] != "nil") || ([:typeof [:find $candidate "/core-"]] != "nil")) do={:set preferred $candidate}
            }
        }
        :set offset ($end + 3)
    }
    :if ($preferred != "") do={:return $preferred}
    :if ($first != "") do={:return $first}
    :error "Twitch homepage has no usable assets.twitch.tv JS URL"
}
:global FHRBenchmark do={
    :global FHRGitHubAsset; :global FHRSignedURL; :global FHRTwitchAsset; :global FHRURL
    :local svc $1; :local rows $2; :local result [:toarray ""]
    :onerror e in={
        :if (($svc->"mode") = "github") do={
            :set result [$FHRGitHubAsset]
            :if ([:len $result] = 0) do={:error "no release asset metadata"}
            :set ($result->"url") [$FHRSignedURL ($result->"public")]
        } else={
            :local u [:tostr ($svc->"testURL")]
            :if ((($svc->"mode") = "twitch") && ($u = "")) do={:set u [$FHRTwitchAsset $rows]}
            :if ($u != "") do={
                :local parsed [$FHRURL $u]
                :local suffix ($svc->"suffix")
                :if (($svc->"mode") = "twitch") do={
                    :if (($parsed->"host") != "assets.twitch.tv") do={:error "Twitch benchmark must be on assets.twitch.tv"}
                    :set suffix 214
                } else={
                    :if (($parsed->"host") != ($svc->"probeHost")) do={:error "custom benchmark must stay on its profile hostname"}
                }
                :set result {"url"=$u;"host"=($parsed->"host");"suffix"=$suffix;"mode"=($svc->"mode")}
            }
        }
    } do={
        :put ("BENCHMARK " . ($svc->"key") . ": unavailable; " . $e)
        :set result [:toarray ""]
    }
    :return $result
}
:global FHRPrepareSample do={
    :global FHRHTTP; :global FHRHeader; :global FHRPop; :global FHRAllowed
    :global FHRSame24; :global FHRRange; :global FHRConfig
    :local bench $1; :local row $2
    :local ip [$FHRSame24 ($row->"ip") ($bench->"suffix")]
    :local r [$FHRHTTP ({"url"=($bench->"url");"ip"=$ip;"method"="head";"seconds"=10})]
    :if ((($r->"code") != 200) || (($r->"requestOK") != true)) do={:return {"ok"=false}}
    :local observed [$FHRPop [$FHRHeader ($r->"http-headers") "x-served-by"]]
    :if (($observed != "?") && (![$FHRAllowed $observed ""])) do={:return {"ok"=false;"excluded"=true}}
    :local encoding [:convert transform=lc [$FHRHeader ($r->"http-headers") "content-encoding"]]
    :if (($encoding != "") && ($encoding != "identity")) do={:return {"ok"=false;"reason"="server ignored Accept-Encoding:identity"}}
    :local length [:tonum [$FHRHeader ($r->"http-headers") "content-length"]]
    :local requested ($FHRConfig->"sampleBytes")
    :if (([:typeof $length] != "nil") && ($length > 0) && ($length <= $requested)) do={
        :return {"ok"=true;"ip"=$ip;"bytes"=$length;"range"=false;"pop"=$observed}
    }
    # Prove byte-range support before requesting part of a potentially huge asset.
    :local q [$FHRHTTP ({"url"=($bench->"url");"ip"=$ip;"method"="get";"headers"="Range:bytes=0-1023";"seconds"=10})]
    :if ((($q->"requestOK") != true) || (($q->"code") != 206)) do={:return {"ok"=false;"reason"="Range unsupported"}}
    :local cr [$FHRRange [$FHRHeader ($q->"http-headers") "content-range"]]
    :if (([:len $cr] = 0) || (($cr->"first") != 0)) do={:return {"ok"=false}}
    :if (($cr->"total") < $requested) do={:set requested ($cr->"total")}
    :set observed [$FHRPop [$FHRHeader ($q->"http-headers") "x-served-by"]]
    :if (($observed != "?") && (![$FHRAllowed $observed ""])) do={:return {"ok"=false;"excluded"=true}}
    :return {"ok"=true;"ip"=$ip;"bytes"=$requested;"range"=true;"pop"=$observed}
}
:global FHRMeasure do={
    :global FHRConfig; :global FHRHTTP; :global FHRSignedURL
    :global FHRPrepareSample; :global FHRHeader; :global FHRPop; :global FHRAllowed
    :local svc $1; :local rows $2; :local bench $3
    :local stats [:toarray ""]; :local prepared [:toarray ""]
    :if ([:len $bench] = 0) do={:return {"samples"=$stats;"bench"=$bench;"measured"=false}}
    :foreach row in=$rows do={
        :local ip ($row->"ip")
        :set ($prepared->$ip) [$FHRPrepareSample $bench $row]
        :set ($stats->$ip) {"rates"=[:toarray ""];"valid"=0;"blocked"=false}
    }
    :for round from=1 to=($FHRConfig->"rounds") do={
        :if (($bench->"mode") = "github") do={
            :onerror e in={:set ($bench->"url") [$FHRSignedURL ($bench->"public")]} do={:error "cannot refresh signed release URL"}
        }
        :put ("SAMPLE " . ($svc->"key") . " round=" . $round . "/" . ($FHRConfig->"rounds"))
        :if ([:len $rows] > 0) do={:for n from=0 to=([:len $rows] - 1) do={
            :local row ($rows->(($n + $round - 1) % [:len $rows])); :local ip ($row->"ip")
            :local prep ($prepared->$ip); :local s ($stats->$ip); :local rate 0; :local code 0; :local ms 0
            :if ((($prep->"ok") = true) && (($s->"blocked") != true)) do={
                :local header ""
                :if (($prep->"range") = true) do={:set header ("Range:bytes=0-" . (($prep->"bytes") - 1))}
                :local r [$FHRHTTP ({"url"=($bench->"url");"ip"=($prep->"ip");"method"="get";"output"="none";"headers"=$header;"seconds"=($FHRConfig->"sampleSeconds")})]
                :set code ($r->"code"); :set ms ($r->"wallMs")
                :local wanted 200; :if (($prep->"range") = true) do={:set wanted 206}
                :local kib [:tonum ($r->"downloaded")]
                :local expected (($prep->"bytes") / 1024)
                :local observed [$FHRPop [$FHRHeader ($r->"http-headers") "x-served-by"]]
                :if (($observed != "?") && (![$FHRAllowed $observed ""])) do={:set ($s->"blocked") true}
                :if ((($r->"requestOK") = true) && (($r->"status") = "finished") && ($code = $wanted) && ([:typeof $kib] != "nil") && ($kib >= ($expected - 1)) && ($ms > 0) && (($s->"blocked") != true)) do={
                    :set rate ((($prep->"bytes") * 8000) / $ms)
                    :set ($s->"valid") (($s->"valid") + 1)
                }
            }
            :set ($s->"rates") (($s->"rates"), $rate); :set ($stats->$ip) $s
            :put ("  " . $ip . " HTTP=" . $code . " wallMs=" . $ms . " approxKbps=" . ($rate / 1000))
        }}
    }
    :return {"samples"=$stats;"bench"=$bench;"measured"=true}
}
