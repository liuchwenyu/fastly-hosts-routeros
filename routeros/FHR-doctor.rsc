
/system resource print
/ip dns print
/ip dhcp-server network print detail
/ip firewall mangle print detail where chain=output
/ip route print detail where dst-address="0.0.0.0/0"
/ip dns static print detail where comment~"^FHR:auto:"
/tool netwatch print detail where comment="FHR:temporary-tcp"
/system scheduler print detail where name~"^FHR[.]"
:put "A DNS override affects only clients querying this router. These commands change no configuration."
