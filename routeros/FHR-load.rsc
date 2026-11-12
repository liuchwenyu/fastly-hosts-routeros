:onerror fhrModuleError in={/system script run FHR.config} do={:error ("FHR.load/config: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.core} do={:error ("FHR.load/core: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.storage} do={:error ("FHR.load/storage: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.network} do={:error ("FHR.load/network: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.benchmarks} do={:error ("FHR.load/benchmarks: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.discovery} do={:error ("FHR.load/discovery: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.dns} do={:error ("FHR.load/dns: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.engine} do={:error ("FHR.load/engine: " . $fhrModuleError)}
:onerror fhrModuleError in={/system script run FHR.commands} do={:error ("FHR.load/commands: " . $fhrModuleError)}
:global FHRLoadSettings; :onerror e in={$FHRLoadSettings} do={:error ("FHR.load/settings: " . $e)}
:global FHRValidateConfig; :onerror e in={$FHRValidateConfig} do={:error ("FHR.load/validation: " . $e)}
