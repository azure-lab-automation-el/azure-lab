$cs = Get-CimInstance Win32_ComputerSystem
"host=$env:COMPUTERNAME domain=$($cs.Domain) partOfDomain=$($cs.PartOfDomain) role=$($cs.DomainRole)"
"cpu=" + (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
"ramMB=" + [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1KB)
"freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
"secureChannel=" + (Test-ComputerSecureChannel)
