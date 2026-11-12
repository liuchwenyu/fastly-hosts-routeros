# Small recoverable JSON files. Probe payloads are never written to storage.
:global FHRDir
:if ([:len [/file find where name="flash"]] > 0) do={:set FHRDir "flash/fhr-state"} else={:set FHRDir "fhr-state"}
:if ([:len [/file find where name=$FHRDir]] = 0) do={/file add name=$FHRDir type=directory}
:global FHRStateStem do={
    :local fhrStateName [:tostr $1]
    :if (!($fhrStateName ~ "^[a-z0-9._-]+\$")) do={:error "unsafe state key"}
    :if ([:len $fhrStateName] > 160) do={:return ("long-" . [:convert transform=md5 to=hex $fhrStateName])}
    :return $fhrStateName
}
:global FHRReadJSON do={
    :global FHRDir; :global FHRStateStem
    :local stem [$FHRStateStem $1]
    :local result [:toarray ""]; :local good false; :local sawFile false
    :foreach suffix in={"";".prev"} do={
        :local path ($FHRDir . "/" . $stem . ".json" . $suffix)
        :if ((!$good) && ([:len [/file find where name=$path]] > 0)) do={
            :set sawFile true
            :local fhrStateText ""
            :onerror fhrAccessError in={
                :set fhrStateText [/file get [/file find where name=$path] contents]
            } do={:error ("state access failed: " . $stem . ": " . $fhrAccessError)}
            :if (([:len $fhrStateText] = 0) && ([/file get [/file find where name=$path] size] > 0)) do={
                :error ("state contents unavailable: " . $stem . "; check sensitive permission; existing files retained")
            }
            :onerror e in={
                :set result [:deserialize from=json options=json.no-string-conversion value=$fhrStateText]
                :if ([:typeof $result] != "array") do={:error "JSON root must be an object or array"}
                :set good true
            } do={:set result [:toarray ""]; :log warning ("FHR: invalid JSON state " . $stem . $suffix . "; checking previous copy")}
        }
    }
    :if ($sawFile && (!$good)) do={:error ("state has no valid JSON copy: " . $stem . "; existing files retained")}
    :return $result
}
:global FHRWriteJSON do={
    :global FHRDir; :global FHRStateStem
    :local fhrStateName [$FHRStateStem $1]; :local value $2
    :if (!($fhrStateName ~ "^[a-z0-9._-]+\$")) do={:error "unsafe state filename"}
    :local text [:serialize to=json options=json.no-string-conversion value=$value]
    :if ([:len $text] > 57000) do={:error "state file exceeds safe 57KB limit"}
    :local path ($FHRDir . "/" . $fhrStateName . ".json"); :local temp ($path . ".new"); :local previous ($path . ".prev")
    :if ([:len [/file find where name=$temp]] > 0) do={/file remove [/file find where name=$temp]}
    /file add name=$temp type=file contents=$text
    :local check [/file get [/file find where name=$temp] contents]
    :if ($check != $text) do={:error "state write did not verify; existing file retained"}
    :local parsed [:deserialize from=json options=json.no-string-conversion value=$check]
    :if ([:typeof $parsed] != "array") do={:error "state write is not valid JSON"}
    :if ([:len [/file find where name=$path]] > 0) do={
        :if ([:len [/file find where name=$previous]] > 0) do={/file remove [/file find where name=$previous]}
        /file set [/file find where name=$path] name=$previous
    }
    /file set [/file find where name=$temp] name=$path
}
:global FHRDeleteState do={
    :global FHRDir; :global FHRStateStem
    :local stem [$FHRStateStem $1]
    :foreach suffix in={"";".prev";".new"} do={
        :local path ($FHRDir . "/" . $stem . ".json" . $suffix)
        :if ([:len [/file find where name=$path]] > 0) do={/file remove [/file find where name=$path]}
    }
}
:global FHRSaveSettings do={
    :global FHRConfig; :global FHRProfiles; :global FHRWriteJSON
    $FHRWriteJSON "settings" ({"config"=$FHRConfig;"profiles"=$FHRProfiles})
}
:global FHRLoadSettings do={
    :global FHRConfig; :global FHRProfiles; :global FHRReadJSON
    :local saved [$FHRReadJSON "settings"]
    :if ([:typeof ($saved->"config")] = "array") do={:foreach k,v in=($saved->"config") do={:if ($k != "version") do={:set ($FHRConfig->$k) $v}}}
    :if ([:typeof ($saved->"profiles")] = "array") do={:foreach k,v in=($saved->"profiles") do={:set ($FHRProfiles->$k) $v}}
}
:global FHRCacheWrite do={
    # Page caches to keep every state file below RouterOS's file/get limit.
    :global FHRWriteJSON; :global FHRReadJSON; :global FHRDeleteState
    :local key [:tostr $1]; :local rows $2; :local pages 0; :local chunk [:toarray ""]
    :local old [$FHRReadJSON ("cache-" . $key)]
    :local generation [:tostr ([:tonsec [:timestamp]] / 1000000000)]
    :foreach row in=$rows do={
        :local compact {"ip"=($row->"ip");"pop"=($row->"pop");"latencyUs"=($row->"latencyUs");"latencyKind"=($row->"latencyKind");"headMs"=($row->"headMs")}
        :set ($chunk->[:len $chunk]) $compact
        :if ([:len $chunk] >= 150) do={
            $FHRWriteJSON ("cache-" . $key . "-" . $generation . "-" . $pages) $chunk
            :set pages ($pages + 1); :set chunk [:toarray ""]
        }
    }
    :if ([:len $chunk] > 0) do={
        $FHRWriteJSON ("cache-" . $key . "-" . $generation . "-" . $pages) $chunk
        :set pages ($pages + 1)
    }
    $FHRWriteJSON ("cache-" . $key) ({"generation"=$generation;"pages"=$pages;"at"=([:tonsec [:timestamp]] / 1000000000)})
    :if ((!([:typeof ($old->"pages")] ~ "^(nil|nothing)\$")) && (($old->"generation") != $generation)) do={
        :if (($old->"pages") > 0) do={:for i from=0 to=(($old->"pages") - 1) do={
            $FHRDeleteState ("cache-" . $key . "-" . ($old->"generation") . "-" . $i)
        }}
    }
}
:global FHRCacheRead do={
    :global FHRReadJSON
    :local key [:tostr $1]; :local index [$FHRReadJSON ("cache-" . $key)]; :local out [:toarray ""]
    :local pages [:tonum ($index->"pages")]
    :if (([:typeof $pages] != "nil") && ($pages > 0) && ($pages < 1000)) do={
        :for i from=0 to=($pages - 1) do={
            :local rows [$FHRReadJSON ("cache-" . $key . "-" . ($index->"generation") . "-" . $i)]
            :foreach row in=$rows do={:if (!([:typeof ($row->"ip")] ~ "^(nil|nothing)\$")) do={:set ($out->[:len $out]) $row}}
        }
    }
    :return {"at"=($index->"at");"rows"=$out}
}
