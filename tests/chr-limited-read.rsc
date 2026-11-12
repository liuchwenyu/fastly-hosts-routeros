# DISPOSABLE CHR ONLY. Verify that hidden file contents never become empty state.
/system script run FHR.load
:global FHRDir; :global FHRWriteJSON; :global FHRDeleteState
$FHRWriteJSON "lab-limited" ({"generation"=1})
:local path ($FHRDir . "/lab-limited.json")
:local before [/file get [find where name=$path] contents]
/system script add name=LAB.limited policy=ftp,read,write,policy,test source={
    :global FHRReadJSON
    :local rejected false
    :onerror e in={:local data [$FHRReadJSON "lab-limited"]} do={
        :if (!($e ~ "state contents unavailable")) do={:error $e}
        :set rejected true
    }
    :if (!$rejected) do={:error "hidden contents were silently accepted"}
    :log info "LAB LIMITED READ PASS: missing sensitive rejected before state changes"
}
/system script run LAB.limited use-script-permissions
:if ([/file get [find where name=$path] contents] != $before) do={:error "limited read changed state"}
$FHRDeleteState "lab-limited"
