$ErrorActionPreference = 'SilentlyContinue'

# CONFIG
$testDomain = "microsoft.com"
$timeoutMs = 2000

# Get DNS info
$forwarders = (Get-DnsServerForwarder -ErrorAction SilentlyContinue).IPAddress
$recursionObj = Get-DnsServerRecursion -ErrorAction SilentlyContinue
$recursion = $false
if ($recursionObj) {
    $recursion = $recursionObj.Enable
}
$rootHints = Get-DnsServerRootHint -ErrorAction SilentlyContinue

# Normalize forwarders
$forwarderList = if ($forwarders) { $forwarders -join "," } else { "None" }

# Test forwarder reachability
$forwarderReachable = $false
foreach ($f in $forwarders) {
    $test = Test-NetConnection -ComputerName $f -Port 53 -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        $forwarderReachable = $true
        break
    }
}

# Test external resolution timing (No Try-Catch)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = Resolve-DnsName $testDomain -Server localhost -ErrorAction SilentlyContinue
$sw.Stop()

# Verify if the resolution succeeded by checking the output object
if ($result) {
    $resolutionTime = $sw.ElapsedMilliseconds
} else {
    $resolutionTime = -1
}

# Determine resolution path (heuristic)
$resolutionPath = "Unknown"
if ($forwarders -and $forwarderReachable) {
    if ($resolutionTime -gt 0 -and $resolutionTime -lt 500) {
        $resolutionPath = "Forwarder"
    }
}
if ($resolutionPath -eq "Unknown" -and $rootHints -and $recursion) {
    if ($resolutionTime -gt 500 -or $forwarders -eq $null) {
        $resolutionPath = "RootHint"
    }
}

# Root hints status
$rootHintsPresent = if ($rootHints) { $true } else { $false }

# Health summary
$summary = "Healthy"

if (-not $recursion) {
    $summary = "NoRecursion"
}
elseif (-not $forwarders) {
    $summary = "RootHintsOnly"
}
elseif (-not $forwarderReachable) {
    $summary = "ForwardersUnreachable"
}
elseif ($resolutionTime -eq -1) {
    $summary = "ResolutionFailed"
}
elseif ($resolutionTime -gt 1000) {
    $summary = "SlowDNS"
}

# Output (PDQ-friendly object)
[PSCustomObject]@{
    ComputerName          = $env:COMPUTERNAME
    Forwarders            = $forwarderList
    ForwarderReachable    = $forwarderReachable
    RecursionEnabled      = $recursion
    RootHintsPresent      = $rootHintsPresent
    ExternalResolutionMs  = $resolutionTime
    ResolutionPath        = $resolutionPath
    Summary               = $summary
}