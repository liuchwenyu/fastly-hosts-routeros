# DISPOSABLE CHR ONLY. Run with the installed script's declared permissions.
# Deliberately corrupts only lab-guard state; never production state.
/system script run FHR.load
:global FHRDir; :global FHRReadJSON; :global FHRWriteJSON; :global FHRDeleteState
$FHRDeleteState "lab-guard"
$FHRWriteJSON "lab-guard" ({"generation"=1})
$FHRWriteJSON "lab-guard" ({"generation"=2})
:local path ($FHRDir . "/lab-guard.json")
/file set [find where name=$path] contents="broken JSON"
:local recovered [$FHRReadJSON "lab-guard"]
:if (($recovered->"generation") != 1) do={:error "valid previous copy not recovered"}
:local previous ($path . ".prev")
/file set [find where name=$previous] contents="also broken JSON"
:local rejected false
:onerror e in={:local data [$FHRReadJSON "lab-guard"]} do={
    :if (!($e ~ "state has no valid JSON copy")) do={:error $e}
    :set rejected true
}
:if (!$rejected) do={:error "invalid state was silently accepted"}
:if ([/file get [find where name=$path] contents] != "broken JSON") do={:error "invalid primary was changed"}
:if ([/file get [find where name=$previous] contents] != "also broken JSON") do={:error "invalid backup was changed"}
$FHRDeleteState "lab-guard"
:log info "LAB STORAGE GUARDS PASS: fallback, fail-closed, both damaged copies preserved"
