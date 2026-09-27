Get-Service NTDS, DNS, ADWS, Netlogon | ForEach-Object { "$($_.Name)=$($_.Status)" }
"resolve esther.lab=" + ((Resolve-DnsName esther.lab -Type A).IPAddress -join ',')
"dc=" + (Get-ADDomainController).HostName
"forestMode=" + (Get-ADForest).ForestMode
"freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
"ramMB=" + [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1KB)
"os=" + (Get-CimInstance Win32_OperatingSystem).Caption
