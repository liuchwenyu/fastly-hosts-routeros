:global FHREvaluate do={
    :global FHRConfig; :global FHRDiscover; :global FHRShortlist
    :global FHRBenchmark; :global FHRMeasure; :global FHRRank
    :local svc $1; :local ranges $2; :local opts $3
    :local rows [$FHRDiscover $svc $ranges ($opts->"refresh") ($opts->"cacheOnly")]
    :local shortlist [$FHRShortlist $svc $rows ($opts->"region") ($opts->"full")]
    :local empty {"ranked"=[:toarray ""];"bench"=[:toarray ""];"measured"=false;"found"=[:len $rows]}
    :if ([:len $shortlist] = 0) do={:return $empty}
    :put ("SHORTLIST " . ($svc->"key") . ": " . [:len $shortlist] . " candidates")
    :local bench [$FHRBenchmark $svc $shortlist]
    :local result [$FHRMeasure $svc $shortlist $bench]
    :local eligible [:toarray ""]
    :foreach row in=$shortlist do={
        :local sample ($result->"samples"->($row->"ip"))
        :if (($sample->"blocked") != true) do={:set ($eligible->[:len $eligible]) $row}
    }
    :local ranked [$FHRRank $eligible ($result->"samples")]
    :foreach row in=$ranked do={
        :put ("RANK " . ($svc->"key") . " " . ($row->"ip") . " POP=" . ($row->"pop") . " smooth=" . ($row->"smooth") . "/" . ($FHRConfig->"rounds") . " medianApproxKbps=" . (($row->"medianBps") / 1000) . " valid=" . ($row->"valid") . " latencyKind=" . ($row->"latencyKind"))
    }
    :if (($result->"measured") != true) do={:put ("UNMEASURED " . ($svc->"key") . ": valid TLS/HTTP routes ranked by available connection timing")}
    :return {"ranked"=$ranked;"bench"=($result->"bench");"measured"=($result->"measured");"found"=[:len $rows]}
}
:global FHREvaluateX do={
    :global FHRProbe; :global FHRAllowed
    :local svc $1; :local donor $2; :local region $3; :local rows [:toarray ""]
    :foreach original in=($donor->"ranked") do={
        :local candidate [$FHRProbe $svc ($original->"ip") false]
        :if ((($candidate->"ok") = true) && (($candidate->"pop") = ($original->"pop")) && [$FHRAllowed ($candidate->"pop") $region]) do={
            :local row $original
            :set ($row->"ip") ($candidate->"ip"); :set ($row->"donorPOP") ($original->"pop")
            :set ($row->"borrowed") true
            :set ($rows->[:len $rows]) $row
        }
    }
    :put ("X PROXY: " . [:len $rows] . " .159 candidates with the same observed POP as their GitHub donor")
    :return {"ranked"=$rows;"bench"=[:toarray ""];"measured"=($donor->"measured");"found"=[:len $rows];"borrowed"=true}
}
:global FHRSelectApply do={
    :global FHRConfig; :global FHRReadJSON; :global FHRPreflight; :global FHRCommit
    :local svc $1; :local evaluated $2; :local opts $3
    :local ranked ($evaluated->"ranked"); :local measured ($evaluated->"measured")
    :local usable [:toarray ""]
    :foreach row in=$ranked do={
        :if ((($measured = true) && (($row->"valid") > 0)) || (($measured != true) && (($FHRConfig->"allowLatencyFallback") = true))) do={:set ($usable->[:len $usable]) $row}
    }
    :if ([:len $usable] = 0) do={
        :put ("NO CHANGE " . ($svc->"key") . ": no usable non-Singapore candidate")
        :return {"result"="no-candidate";"key"=($svc->"key")}
    }
    :local current [$FHRReadJSON ("current-" . ($svc->"key"))]
    :local best ($usable->0); :local sticky [:toarray ""]
    :if (($measured = true) && (($FHRConfig->"stickyPercent") > 0)) do={
        :foreach row in=$usable do={
            :if ((($row->"ip") = ($current->"ip")) && (($row->"smooth") = ($best->"smooth")) && (($row->"valid") >= ($best->"valid")) && (($row->"medianBps") > 0) && (($best->"medianBps") * 100 <= ($row->"medianBps") * (100 + ($FHRConfig->"stickyPercent")))) do={:set sticky $row}
        }
    }
    :if ([:len $sticky] > 0) do={
        :local reordered [:toarray ""]; :set ($reordered->0) $sticky
        :foreach row in=$usable do={:if (($row->"ip") != ($sticky->"ip")) do={:set ($reordered->[:len $reordered]) $row}}
        :set usable $reordered
    }
    # Fresh group validation and automatic fail-through: no manual candidate gate.
    :foreach row in=$usable do={
        :local proof [$FHRPreflight $svc $row ($evaluated->"bench") ($opts->"region")]
        :if (($proof->"ok") = true) do={
            :set ($row->"pop") ($proof->"pop")
            :if (($opts->"apply") = true) do={
                :local changed [$FHRCommit $svc $row]
                :return {"result"="applied-or-kept";"key"=($svc->"key");"ip"=($row->"ip");"pop"=($row->"pop");"measured"=$measured;"changed"=$changed}
            }
            :put ("TEST SELECT " . ($svc->"key") . " " . ($row->"ip") . " POP=" . ($row->"pop"))
            :return {"result"="test-only";"key"=($svc->"key");"ip"=($row->"ip");"pop"=($row->"pop");"measured"=$measured}
        }
        :put ("REJECT ON FINAL CHECK " . ($svc->"key") . " " . ($row->"ip") . "; trying next ranked candidate")
    }
    :return {"result"="final-check-failed";"key"=($svc->"key")}
}
:global FHRRunServices do={
    :global FHRProfiles; :global FHRRanges; :global FHREvaluate; :global FHREvaluateX
    :global FHRSelectApply; :global FHRDiscover; :global FHRWriteJSON
    :local opts $1; :local only [:tostr ($opts->"service")]
    :if (($only != "") && ([:typeof ($FHRProfiles->$only)] ~ "^(nil|nothing)\$")) do={:error "unknown service"}
    :local ranges [$FHRRanges]; :local evaluated [:toarray ""]; :local report [:toarray ""]
    :local useX false
    :if (((($FHRProfiles->"x"->"enabled") = true) && ($only = "")) || ($only = "x")) do={:set useX true}
    :local order {"github";"twitch"}
    :foreach key,svc in=$FHRProfiles do={:if (($key != "github") && ($key != "x") && ($key != "twitch")) do={:set ($order->[:len $order]) $key}}
    :foreach key in=$order do={
        :local svc ($FHRProfiles->$key)
        :local requested (((($svc->"enabled") = true) && ($only = "")) || ($only = $key))
        :local dependency (($key = "github") && $useX)
        :if ($requested || $dependency) do={
            :put ("=== SERVICE " . $key . " ===")
            :onerror e in={
                :if (($opts->"scanOnly") = true) do={
                    :local rows [$FHRDiscover $svc $ranges true false]
                    :set ($report->$key) {"result"="scanned";"count"=[:len $rows]}
                } else={
                    :local result [$FHREvaluate $svc $ranges $opts]
                    :set ($evaluated->$key) $result
                    :if ($requested) do={:set ($report->$key) [$FHRSelectApply $svc $result $opts]}
                }
            } do={
                :set ($report->$key) {"result"="error";"error"=[:tostr $e]}
                :log error ("FHR " . $key . ": " . $e); :put ("SERVICE FAILED " . $key . ": " . $e)
            }
        }
    }
    :if ($useX && (($opts->"scanOnly") != true)) do={
        :onerror e in={
            :local donor ($evaluated->"github")
            :if ([:typeof $donor] != "array") do={:error "GitHub donor ranking unavailable"}
            :local result [$FHREvaluateX ($FHRProfiles->"x") $donor ($opts->"region")]
            :set ($report->"x") [$FHRSelectApply ($FHRProfiles->"x") $result $opts]
        } do={:set ($report->"x") {"result"="error";"error"=[:tostr $e]}; :put ("SERVICE FAILED x: " . $e)}
    }
    :onerror e in={$FHRWriteJSON "last-report" ({"at"=([:tonsec [:timestamp]] / 1000000000);"results"=$report})} do={:log warning ("FHR report save: " . $e)}
    :put "=== RESULT ==="
    :foreach key,r in=$report do={:put ($key . ": " . ($r->"result") . " " . [:tostr ($r->"ip")] . " " . [:tostr ($r->"pop")])}
    :return $report
}
:global FHRHealth do={
    :global FHRProfiles; :global FHRConfig; :global FHRReadJSON; :global FHRWriteJSON
    :global FHRPreflight; :global FHRCommit; :global FHRRestore
    :local failures [$FHRReadJSON "health"]
    :foreach key,svc in=$FHRProfiles do={
        :local current [$FHRReadJSON ("current-" . $key)]
        :if ((($svc->"enabled") = true) && ([:tostr ($current->"ip")] != "")) do={
            :local row $current
            :if (($svc->"mode") = "via") do={:set ($row->"donorPOP") ($current->"pop")}
            :local proof [$FHRPreflight $svc $row [:toarray ""] ($FHRConfig->"region")]
            :local count [:tonum ($failures->$key)]; :if ([:typeof $count] = "nil") do={:set count 0}
            :if (($proof->"ok") = true) do={:set count 0} else={:set count ($count + 1)}
            :set ($failures->$key) $count
            :if ($count >= ($FHRConfig->"healthFailures")) do={
                :local old [$FHRReadJSON ("previous-" . $key)]; :local previous ($old->"current"); :local recovered false
                :if ([:tostr ($previous->"ip")] != "") do={
                    :if (($svc->"mode") = "via") do={:set ($previous->"donorPOP") ($previous->"pop")}
                    :local test [$FHRPreflight $svc $previous [:toarray ""] ($FHRConfig->"region")]
                    :if (($test->"ok") = true) do={
                        :set ($previous->"pop") ($test->"pop")
                        :local changed [$FHRCommit $svc $previous]
                        :set recovered true; :put ("HEALTH ROLLBACK " . $key)
                    }
                }
                :if ((!$recovered) && (($FHRConfig->"healthFailOpen") = true)) do={
                    $FHRRestore $key
                    :put ("HEALTH FALLBACK " . $key . ": automatic DNS override removed; upstream DNS may return Singapore")
                }
                :set ($failures->$key) 0
            }
        }
    }
    $FHRWriteJSON "health" $failures
}
