/system script run FHR.load
# Local deterministic checks. No HTTP, DNS changes, routes, NAT or mangle writes.
# Includes a small state-file roundtrip. Installed modules must already be loaded.
:global FHRTrim; :global FHRSplit; :global FHRHeader; :global FHRPop
:global FHRIPNum; :global FHRNumIP; :global FHRSame24; :global FHRCIDR; :global FHRInRanges; :global FHRBlocks
:global FHRAllowed; :global FHRHostValid; :global FHRURL; :global FHRMedian; :global FHRRank; :global FHRRange
:global FHRConfig; :global FHRProfiles; :global FHRReadJSON; :global FHRWriteJSON; :global FHRDeleteState; :global FHRDir
:global FHRTestCount 0
:global FHRAssert do={
    :global FHRTestCount
    :if ($1 != true) do={:error ("SELFTEST FAILED: " . $2)}
    :set FHRTestCount ($FHRTestCount + 1)
}
:local originalConfig [:deserialize from=json options=json.no-string-conversion value=[:serialize to=json options=json.no-string-conversion value=$FHRConfig]]
:local failed ""
:onerror e in={
    # The lookup variable must be distinct from the RouterOS name property.
    :local fhrExpectedScriptName "FHR.config"
    :local fhrLookupIds [/system script find where name=$fhrExpectedScriptName]
    $FHRAssert ([:len $fhrLookupIds] = 1) "exact script lookup count"
    $FHRAssert ([/system script get ($fhrLookupIds->0) name] = $fhrExpectedScriptName) "exact script lookup identity"
    :local fhrAbsentScriptName ("FHR.selftest.absent." . [:tostr [:tonsec [:timestamp]]])
    $FHRAssert ([:len [/system script find where name=$fhrAbsentScriptName]] = 0) "missing script lookup stays empty"
    $FHRAssert ([:len [/system scheduler find where name=$fhrAbsentScriptName]] = 0) "missing scheduler lookup stays empty"
    :set ($FHRConfig->"excluded") "|SIN|QPG|"
    :set ($FHRConfig->"smoothFloorBps") 3000000
    :set ($FHRConfig->"smoothPercent") 30
    $FHRAssert ([$FHRTrim (" \tvalue\r\n")] = "value") "trim"
    $FHRAssert ([:len [$FHRSplit "a,b,c" ","]] = 3) "split"
    :local h {"Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'";"x-SeRvEd-By: cache-nrt-test-NRT"}
    $FHRAssert ([$FHRHeader $h "X-Served-By"] = "cache-nrt-test-NRT") "header array"
    $FHRAssert ([$FHRHeader ({"x-served-by"="cache-itm-test-ITM"}) "X-Served-By"] = "cache-itm-test-ITM") "header map"
    $FHRAssert ([$FHRHeader ({"Location: https://example.com/a;b?x=1&y=2"}) "location"] = "https://example.com/a;b?x=1&y=2") "header value semicolon"
    $FHRAssert ([$FHRPop "cache-nrt-rjtf7700089-NRT"] = "NRT") "simple POP"
    $FHRAssert ([$FHRPop "t4_p, cache-nrt-rjaa8190044-NRT, cache-sin-wsat1880090-SIN, cache-tw-ZZZ1"] = "SIN") "last valid cache POP"
    $FHRAssert ([$FHRPop "cache-tw-ZZZ1"] = "?") "invalid suffix rejected"
    $FHRAssert ([$FHRPop ""] = "?") "empty POP"
    $FHRAssert ([$FHRIPNum "255.255.255.255"] = 4294967295) "IPv4 maximum"
    $FHRAssert ([$FHRNumIP 4294967295] = "255.255.255.255") "IPv4 inverse"
    $FHRAssert ([$FHRSame24 "146.75.48.133" 159] = "146.75.48.159") "suffix substitution"
    :local c [$FHRCIDR "151.101.129.3/16"]
    $FHRAssert ([$FHRNumIP ($c->"base")] = "151.101.0.0") "CIDR normalization"
    :local b [$FHRBlocks ({"10.0.0.0/23";"10.0.1.0/24"}) 100]
    $FHRAssert ([:len $b] = 2) "all /24 blocks, deduplicated"
    $FHRAssert ([$FHRInRanges "151.101.192.133" ({"151.101.0.0/16"})]) "membership"
    $FHRAssert (![$FHRInRanges "8.8.8.8" ({"151.101.0.0/16"})]) "foreign IPv4"
    $FHRAssert (![$FHRAllowed "SIN" ""]) "SIN excluded"
    $FHRAssert (![$FHRAllowed "QPG" ""]) "QPG excluded"
    $FHRAssert ([$FHRAllowed "NRT" "NRT"]) "requested region"
    $FHRAssert (![$FHRAllowed "ITM" "NRT"]) "different region"
    $FHRAssert (![$FHRAllowed "?" ""]) "unknown region"
    $FHRAssert ([$FHRHostValid "files.pythonhosted.org"]) "custom hostname"
    $FHRAssert (![$FHRHostValid ("x\r\n.example.com")]) "host control characters"
    $FHRAssert (![$FHRHostValid "127.0.0.1"]) "IP literal not hostname"
    :local u [$FHRURL "https://example.com/a?x=1&y=2"]
    $FHRAssert (($u->"host") = "example.com") "URL hostname"
    $FHRAssert (($u->"path") = "/a?x=1&y=2") "URL query preservation"
    :local rejected false
    :onerror err in={:local x [$FHRURL "http://example.com/"]} do={:set rejected true}
    $FHRAssert $rejected "HTTP downgrade rejected"
    $FHRAssert ([$FHRMedian ({10;1;5})] = 5) "median odd"
    $FHRAssert ([$FHRMedian ({10;1})] = 5) "median integer even"
    :local rows [:toarray ""]
    :set ($rows->0) {"ip"="1.1.1.133";"latencyUs"=9000}
    :set ($rows->1) {"ip"="2.2.2.133";"latencyUs"=1000}
    $FHRAssert (([:len $rows] = 2) && (($rows->0->"ip") = "1.1.1.133")) "array of dictionaries not flattened"
    :local samples [:toarray ""]
    :set ($samples->"1.1.1.133") {"rates"={10000000;10000000;10000000};"valid"=3}
    :set ($samples->"2.2.2.133") {"rates"={20000000;1000000;20000000};"valid"=3}
    :local ranked [$FHRRank $rows $samples]
    $FHRAssert (($ranked->0->"ip") = "1.1.1.133") "smooth count before peak/median"
    $FHRAssert (($ranked->0->"smooth") = 3) "smooth count threshold"
    :local noSpeed [$FHRRank $rows [:toarray ""]]
    $FHRAssert (($noSpeed->0->"ip") = "2.2.2.133") "latency fallback"
    :local range [$FHRRange "bytes 0-1023/8388608"]
    $FHRAssert ((($range->"first") = 0) && (($range->"total") = 8388608)) "Content-Range"
    $FHRAssert ([:len [$FHRRange "bytes 0-1023/*"]] = 0) "unknown size rejected"
    $FHRAssert ([:len ($FHRProfiles->"github"->"hosts")] = 2) "GitHub alias count"
    $FHRAssert ([:len ($FHRProfiles->"twitch"->"hosts")] = 5) "Twitch alias count"
    $FHRAssert (($FHRProfiles->"x"->"suffix") = 159) "X suffix"
    $FHRAssert (($FHRProfiles->"twitch"->"hosts"->"k.twitchcdn.net") = 167) "Twitch secondary suffix"
    $FHRWriteJSON "selftest" ({"test"=true;"ip"="151.101.192.133";"rows"=$rows})
    :local saved [$FHRReadJSON "selftest"]
    $FHRAssert ((($saved->"test") = true) && (($saved->"rows"->1->"ip") = "2.2.2.133")) "state-file roundtrip"
    :local path ($FHRDir . "/selftest.json")
    :local chunk [/file read file=$path offset=0 chunk-size=4 as-value]
    $FHRAssert ([:len [:tostr ($chunk->"data")]] = 4) "native chunked file read"
    # Replace an existing state file and read the previous generation.
    $FHRWriteJSON "selftest" ({"test"=true;"ip"="151.101.192.133";"generation"=2})
    :local revised [$FHRReadJSON "selftest"]
    $FHRAssert (($revised->"generation") = 2) "existing state replaced with declared permissions"
    :local priorPath ($path . ".prev")
    :local prior [:deserialize from=json options=json.no-string-conversion value=[/file get [/file find where name=$priorPath] contents]]
    $FHRAssert (($prior->"rows"->1->"ip") = "2.2.2.133") "renamed prior state remains readable"
    $FHRDeleteState "selftest"
} do={:set failed [:tostr $e]}
:set FHRConfig $originalConfig
:onerror e in={$FHRDeleteState "selftest"} do={}
:if ($failed != "") do={:error $failed}
:put ("SELFTEST PASS: " . $FHRTestCount . " native local checks; no Internet/DNS/routing changes")
