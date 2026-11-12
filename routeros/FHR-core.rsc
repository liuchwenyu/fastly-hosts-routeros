# Pure helpers. All network and configuration writes live in other modules.
:global FHRTrim do={
    :local s [:tostr $1]
    :while ([:len $s] > 0) do={
        :local c [:pick $s 0 1]
        :if (($c = " ") || ($c = "\r") || ($c = "\n") || ($c = "\t")) do={:set s [:pick $s 1 [:len $s]]} else={:break}
    }
    :while ([:len $s] > 0) do={
        :local c [:pick $s ([:len $s] - 1) [:len $s]]
        :if (($c = " ") || ($c = "\r") || ($c = "\n") || ($c = "\t")) do={:set s [:pick $s 0 ([:len $s] - 1)]} else={:break}
    }
    :return $s
}
:global FHRSplit do={
    :local s [:tostr $1]; :local sep [:tostr $2]; :local out [:toarray ""]; :local pos 0
    :if ([:len $sep] = 0) do={:error "split: empty separator"}
    :while ($pos <= [:len $s]) do={
        :local end [:find $s $sep $pos]
        :if ([:typeof $end] = "nil") do={:set out ($out, [:pick $s $pos [:len $s]]); :break}
        :set out ($out, [:pick $s $pos $end]); :set pos ($end + [:len $sep])
    }
    :return $out
}
:global FHRHeader do={
    :global FHRTrim; :global FHRSplit
    :local headers $1; :local wanted [:convert transform=lc [:tostr $2]]
    :if ([:typeof $headers] = "array") do={
        :foreach k,v in=$headers do={
            :if ([:convert transform=lc [:tostr $k]] = $wanted) do={:return [$FHRTrim $v]}
            :local line [:tostr $v]; :local p [:find $line ":"]
            :if ([:typeof $p] != "nil") do={
                :if ([:convert transform=lc [$FHRTrim [:pick $line 0 $p]]] = $wanted) do={:return [$FHRTrim [:pick $line ($p + 1) [:len $line]]]}
            }
        }
    } else={
        # Legacy text fallback. The observed 7.24.5 representation is an array.
        :foreach line in=[$FHRSplit [:tostr $headers] ("\n")] do={
            :foreach piece in=[$FHRSplit $line ";"] do={
                :local p [:find $piece ":"]
                :if ([:typeof $p] != "nil") do={
                    :if ([:convert transform=lc [$FHRTrim [:pick $piece 0 $p]]] = $wanted) do={:return [$FHRTrim [:pick $piece ($p + 1) [:len $piece]]]}
                }
            }
        }
    }
    :return ""
}
:global FHRPop do={
    :global FHRSplit; :global FHRTrim
    :local answer "?"
    :foreach item in=[$FHRSplit [:tostr $1] ","] do={
        :local parts [$FHRSplit [$FHRTrim $item] "-"]
        :if ([:len $parts] >= 3) do={
            :local last [:tostr ($parts->([:len $parts] - 1))]
            :if ((($parts->0) = "cache") && ($last ~ "^[A-Za-z]{3}\$")) do={:set answer [:convert transform=uc $last]}
        }
    }
    :return $answer
}
:global FHRIPNum do={
    :global FHRSplit
    :local parts [$FHRSplit [:tostr $1] "."]; :local out 0
    :if ([:len $parts] != 4) do={:error "invalid IPv4"}
    :foreach s in=$parts do={
        :if (!([:tostr $s] ~ "^[0-9]{1,3}\$")) do={:error "invalid IPv4 octet"}
        :local n [:tonum $s]
        :if (($n < 0) || ($n > 255)) do={:error "invalid IPv4 octet"}
        :set out ($out * 256 + $n)
    }
    :return $out
}
:global FHRNumIP do={
    :local n [:tonum $1]
    :if (($n < 0) || ($n > 4294967295)) do={:error "IPv4 number out of range"}
    :return (($n / 16777216) . "." . (($n / 65536) % 256) . "." . (($n / 256) % 256) . "." . ($n % 256))
}
:global FHRSame24 do={
    :global FHRIPNum; :global FHRNumIP
    :local s [:tonum $2]
    :if (([:typeof $s] = "nil") || ($s < 0) || ($s > 255)) do={:error "invalid suffix"}
    :local n [$FHRIPNum $1]
    :return [$FHRNumIP (($n / 256) * 256 + $s)]
}
:global FHRCIDR do={
    :global FHRIPNum
    :local s [:tostr $1]; :local slash [:find $s "/"]
    :if ([:typeof $slash] = "nil") do={:error "CIDR has no prefix length"}
    :local bits [:tonum [:pick $s ($slash + 1) [:len $s]]]
    :if (([:typeof $bits] = "nil") || ($bits < 0) || ($bits > 32)) do={:error "invalid CIDR prefix"}
    :local n [$FHRIPNum [:pick $s 0 $slash]]; :local size 1
    :if ($bits < 32) do={:for i from=1 to=(32 - $bits) do={:set size ($size * 2)}}
    :local base (($n / $size) * $size)
    :return {"base"=$base;"last"=($base + $size - 1);"prefix"=$bits}
}
:global FHRInRanges do={
    :global FHRIPNum; :global FHRCIDR
    :local n [$FHRIPNum $1]
    :foreach cidr in=$2 do={
        :local r [$FHRCIDR $cidr]
        :if (($n >= ($r->"base")) && ($n <= ($r->"last"))) do={:return true}
    }
    :return false
}
:global FHRBlocks do={
    :global FHRCIDR; :global FHRNumIP
    :local blocks [:toarray ""]; :local seen [:toarray ""]; :local maximum [:tonum $2]
    :foreach cidr in=$1 do={
        :local r [$FHRCIDR $cidr]; :local first ((($r->"base") / 256) * 256); :local last ((($r->"last") / 256) * 256)
        :for n from=$first to=$last step=256 do={
            :local ip [$FHRNumIP $n]
            :if ([:typeof ($seen->$ip)] ~ "^(nil|nothing)\$") do={
                :set ($seen->$ip) true; :set ($blocks->[:len $blocks]) $ip
                :if ([:len $blocks] > $maximum) do={:error "CIDR expansion exceeds maxBlocks; nothing was silently truncated"}
            }
        }
    }
    :return $blocks
}
:global FHRAllowed do={
    :global FHRConfig
    :local pop [:convert transform=uc [:tostr $1]]; :local region [:convert transform=uc [:tostr $2]]
    :if (!($pop ~ "^[A-Z]{3}\$")) do={:return false}
    :if ([:typeof [:find ($FHRConfig->"excluded") ("|" . $pop . "|")]] != "nil") do={:return false}
    :if (($region != "") && ($pop != $region)) do={:return false}
    :return true
}
:global FHRHostValid do={
    :global FHRSplit
    :local h [:tostr $1]
    :if (([:len $h] < 3) || ([:len $h] > 253)) do={:return false}
    :local labels [$FHRSplit $h "."]
    :if ([:len $labels] < 2) do={:return false}
    :foreach label in=$labels do={
        :if (([:len $label] < 1) || ([:len $label] > 63)) do={:return false}
        :if (!($label ~ "^[a-z0-9]([a-z0-9-]*[a-z0-9])?\$")) do={:return false}
    }
    :local tld [:tostr ($labels->([:len $labels] - 1))]
    :if (!($tld ~ "^[a-z]{2,63}\$")) do={:return false}
    :return true
}
:global FHRURL do={
    :global FHRHostValid
    :local u [:tostr $1]
    :if ([:pick $u 0 8] != "https://") do={:error "only HTTPS URLs are accepted"}
    :local slash [:find $u "/" 8]
    :if ([:typeof $slash] = "nil") do={:set u ($u . "/"); :set slash ([:len $u] - 1)}
    :local h [:convert transform=lc [:pick $u 8 $slash]]
    :if (![$FHRHostValid $h]) do={:error "URL must use a DNS hostname without credentials or a nonstandard port"}
    :if (($u ~ "[\r\n]") || ([:typeof [:find $u "#"]] != "nil")) do={:error "invalid URL control character or fragment"}
    :return {"url"=$u;"host"=$h;"path"=[:pick $u $slash [:len $u]]}
}
:global FHRMedian do={
    :local values $1; :local sorted [:toarray ""]
    :foreach n in=$values do={
        :local added false; :local next [:toarray ""]
        :foreach q in=$sorted do={
            :if ((!$added) && ($n < $q)) do={:set ($next->[:len $next]) $n; :set added true}
            :set ($next->[:len $next]) $q
        }
        :if (!$added) do={:set ($next->[:len $next]) $n}
        :set sorted $next
    }
    :local count [:len $sorted]
    :if ($count = 0) do={:return 0}
    :if (($count % 2) = 1) do={:return ($sorted->($count / 2))}
    :return ((($sorted->($count / 2 - 1)) + ($sorted->($count / 2))) / 2)
}
:global FHRBetter do={
    # Upstream ordering: smooth count, median throughput, connection latency.
    # Stable deterministic IP order is the final tie-break, not a POP preference.
    :local a $1; :local b $2
    :if ([:len $b] = 0) do={:return true}
    :if (($a->"smooth") != ($b->"smooth")) do={:return (($a->"smooth") > ($b->"smooth"))}
    :if (($a->"medianBps") != ($b->"medianBps")) do={:return (($a->"medianBps") > ($b->"medianBps"))}
    :if (($a->"latencyUs") != ($b->"latencyUs")) do={:return (($a->"latencyUs") < ($b->"latencyUs"))}
    :global FHRIPNum
    :return ([$FHRIPNum ($a->"ip")] < [$FHRIPNum ($b->"ip")])
}
:global FHRRank do={
    :global FHRConfig; :global FHRMedian; :global FHRBetter
    :local rows $1; :local samples $2; :local peak 0; :local out [:toarray ""]
    :foreach key,s in=$samples do={:foreach value in=($s->"rates") do={:if ($value > $peak) do={:set peak $value}}}
    :local threshold ($peak * ($FHRConfig->"smoothPercent") / 100)
    :if ($threshold < ($FHRConfig->"smoothFloorBps")) do={:set threshold ($FHRConfig->"smoothFloorBps")}
    :foreach row in=$rows do={
        :local s ($samples->($row->"ip")); :local rates [:toarray ""]
        :local smooth 0; :local valid 0
        :if ([:typeof $s] = "array") do={:set rates ($s->"rates"); :set valid ($s->"valid")}
        :foreach rate in=$rates do={:if ($rate >= $threshold) do={:set smooth ($smooth + 1)}}
        :set ($row->"smooth") $smooth; :set ($row->"valid") $valid
        :set ($row->"medianBps") [$FHRMedian $rates]
        :set ($row->"thresholdBps") $threshold; :set ($row->"samples") $rates
        :local next [:toarray ""]; :local added false
        :foreach old in=$out do={
            :if ((!$added) && [$FHRBetter $row $old]) do={:set ($next->[:len $next]) $row; :set added true}
            :set ($next->[:len $next]) $old
        }
        :if (!$added) do={:set ($next->[:len $next]) $row}
        :set out $next
    }
    :return $out
}
:global FHRRange do={
    :global FHRSplit
    :local text [:tostr $1]
    :if ([:pick $text 0 6] != "bytes ") do={:return [:toarray ""]}
    :local range [$FHRSplit [:pick $text 6 [:len $text]] "/"]
    :if ([:len $range] != 2) do={:return [:toarray ""]}
    :local span [$FHRSplit ($range->0) "-"]
    :if ([:len $span] != 2) do={:return [:toarray ""]}
    :local first [:tonum ($span->0)]; :local last [:tonum ($span->1)]; :local total [:tonum ($range->1)]
    :if (([:typeof $first] = "nil") || ([:typeof $last] = "nil") || ([:typeof $total] = "nil")) do={:return [:toarray ""]}
    :if (($first < 0) || ($last < $first) || ($total <= $last)) do={:return [:toarray ""]}
    :return {"first"=$first;"last"=$last;"total"=$total}
}
