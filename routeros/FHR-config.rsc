# Fastly Hosts RouterOS - configuration and service profiles
# MIT; derived from AFAlimru/fastly-hosts-adjust v0.8.3 (see LICENSE).
# This file supplies defaults; saved settings take precedence on later loads.
:global FHRConfig
:global FHRProfiles
:set FHRConfig {
    "version"="1.0.0";
    "excluded"="|SIN|QPG|";
    "region"="";
    "parallel"=8;
    "rounds"=3;
    "shortlist"=10;
    "sampleBytes"=8388608;
    "sampleSeconds"=20;
    "probeSeconds"=6;
    "smoothFloorBps"=3000000;
    "smoothPercent"=30;
    "stickyPercent"=20;
    "cacheSeconds"=86400;
    "cacheStaleSeconds"=604800;
    "dnsTTL"="5m";
    "sourceAddress"="0.0.0.0";
    "vrf"="";
    "resolver"="";
    "maxTextBytes"=1048576;
    "maxBlocks"=16384;
    "healthFailures"=3;
    "healthFailOpen"=true;
    "adoptLegacy"=true;
    "allowLatencyFallback"=true;
    "nearMarginMs"=60;
    "latencyProbe"="tcp";
    "verbose"=false;
    "releaseRepos"={"ollama/ollama";"cli/cli";"AFAlimru/fastly-hosts-adjust"};
    "priorityBlocks"={"151.101.192.0";"151.101.0.0";"151.101.64.0";"151.101.128.0";"167.82.0.0";"167.82.32.0";"199.232.160.0"};
    "fallbackCIDRs"={"23.235.32.0/20";"43.249.72.0/22";"90.98.0.0/17";"90.98.128.0/18";"103.244.50.0/24";"103.245.222.0/23";"103.245.224.0/24";"104.156.80.0/20";"140.248.64.0/18";"140.248.128.0/17";"146.75.0.0/17";"151.101.0.0/16";"157.52.64.0/18";"167.82.0.0/17";"167.82.128.0/20";"167.82.160.0/20";"167.82.224.0/20";"172.111.64.0/18";"185.31.16.0/22";"199.27.72.0/21";"199.232.0.0/16"}
}
:set FHRProfiles [:toarray ""]
:set ($FHRProfiles->"github") {
    "key"="github";"enabled"=true;"mode"="github";
    "probeHost"="raw.githubusercontent.com";
    "probePath"="/github/gitignore/main/README.md";"suffix"=133;
    "anyStatus"=false;"popHost"="";"testURL"="";
    "hosts"={"raw.githubusercontent.com"=133;"release-assets.githubusercontent.com"=133};
    "paths"={"raw.githubusercontent.com"="/github/gitignore/main/README.md";"release-assets.githubusercontent.com"="/"}
}
:set ($FHRProfiles->"x") {
    "key"="x";"enabled"=true;"mode"="via";"via"="github";
    "probeHost"="pbs.twimg.com";
    "probePath"="/profile_images/1683325380441128960/yRsRRjGO_400x400.jpg";
    "suffix"=159;"anyStatus"=false;"popHost"="";"testURL"="";
    "hosts"={"pbs.twimg.com"=159};
    "paths"={"pbs.twimg.com"="/profile_images/1683325380441128960/yRsRRjGO_400x400.jpg"}
}
:set ($FHRProfiles->"twitch") {
    "key"="twitch";"enabled"=true;"mode"="twitch";
    "probeHost"="static-cdn.jtvnw.net";
    "probePath"="/jtv_user_pictures/xarth/404_user_70x70.png";
    "suffix"=214;"anyStatus"=false;
    "popHost"="k.twitchcdn.net";"popPath"="/";"popSuffix"=167;
    "testURL"="";
    "hosts"={"www.twitch.tv"=214;"gql.twitch.tv"=214;"static-cdn.jtvnw.net"=214;"assets.twitch.tv"=214;"k.twitchcdn.net"=167};
    "paths"={"www.twitch.tv"="/";"gql.twitch.tv"="/";"static-cdn.jtvnw.net"="/jtv_user_pictures/xarth/404_user_70x70.png";"assets.twitch.tv"="/";"k.twitchcdn.net"="/"}
}
