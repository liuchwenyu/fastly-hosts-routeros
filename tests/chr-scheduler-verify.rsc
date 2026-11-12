# DISPOSABLE CHR ONLY. Run after reimport on the prepared test installation.
# Every on-event disables itself before executing. Never runs network probes.
/system script set [find where name="LAB.health"] policy=ftp,read,write,policy,test,sensitive
/system scheduler set [find where name="LAB.health"] policy=ftp,read,write,policy,test,sensitive disabled=no
:put "LAB: fixed scheduler armed; expect LAB HEALTH PASS and retained eight DNS records"
