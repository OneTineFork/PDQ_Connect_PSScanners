CIMResponsivenessCriticalClassPresence: This one has been very useful in our server fleet in particular to identify a small number of servers with Missing/broken MSFT classes. These servers were generally sluggish, sometimes virtually unusable. Troubleshooting (DISM, SFC) proved ineffective, but an Repair Install using a current .iso for the Windows Server Version has resolved in all cases.

CriticalEventCheck: This one returns too many results for my taste, but a deeper review of the data might help me to narrow it down to some actionable items.

DNSConfigurationCheck: I work for a relatively large, distributed organization. If we retire a DC or add a new one, there are often DHCP scopes that are missed during followup. This helps me to home in on those.

DirtyBitCheck: We've gotten a few hits with this scanner. They may resolve on their own, or they may require a manual chkdsk to clean up.

GhostUSBDevicesandDisconnectLoops: This is more of a concept, at this point, I haven't seen any hits, yet. The intent is to id failing laptop docks, bad USB-C cables, or failing internal webcams/bluetooth modules.

Memory-Paging-Resource-CorruptionSignals: This one generates too many results, as well, and I haven't determined if any of them are actionable. I intend to keep it running for a while, though, and look for actionable results.

ResourceMonitor: I won't leave this one running, but since we can "validate" a disabled scanner against a single device it could possibly be useful on rare occasions.

RetrieveMACAddress: This one is probably not interesting to anyone else. We had an issue with Sonicwall's GVPN client deployed incorrectly to our golden image, resulting in every imaged device sharing the same MAC. Caused a lot of trouble with folks getting disconnected. Maybe it can be adapted for other uses.

SSD Health Check: This one needs work. It has helped us ID an SSD nearing its end of durability, but frankly doesn't return data for most devices. I'll be working to improve it.

SecureBootCertCheck: This has been very helpful as we near the expiration of old secure boot certs. I guess I'll leave it here for the next round in 15 years.

SubnetsMissingfromADSS: As a large, distributed organization, we're frequently spinning up new small offices and often their subnets don't get entered in ADSS. This scanner peruses netlogon.log and returns entries reporting NO_CLIENT_SITE so we can ensure we're keeping up with location changes.

SystemStabilityCheck: Too many results for me to consider this useful, right now, but maybe I can improve it in the future.

TemperatureCheck: This one is just for fun.

WHEA-PotentialHardwareFailure: Again, too many positive results. This one looks for critical and error events from Microsoft-Windows-WHEA-Logger in the last 2 weeks. Digging into the event details individually is probably not feasible, it'd be a full time job by itself.

WMIRepositoryVerification: Self explanatory. So far no positives, but I'll leave this scanner disabled and turn it on for a few days at a time to see if it ever identifies actionable issues.
