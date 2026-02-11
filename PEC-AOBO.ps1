<#
.SYNOPSIS
    PEC AOBO Foreign Principal RBAC Assignment TUI

.DESCRIPTION
    Interactive TUI for MSPs to assign PEC-eligible RBAC roles to a Foreign Principal
    (ForeignGroup) on customer Azure subscriptions via Admin on Behalf Of (AOBO).

.PARAMETER DryRun
    If specified, shows what would be done without making any changes.

.EXAMPLE
    .\PEC-AOBO.ps1
    .\PEC-AOBO.ps1 -DryRun

.NOTES
    Requires: Az.Accounts, Az.Resources modules
    Source: https://learn.microsoft.com/en-us/partner-center/billing/azure-roles-perms-pec
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ── ANSI color helpers ──────────────────────────────────────────────────────────

function Write-Color {
    param(
        [string]$Text,
        [ValidateSet("Red","Green","Yellow","Blue","Magenta","Cyan","White","Gray","DarkGray")]
        [string]$Color = "White",
        [switch]$NoNewline
    )
    $codes = @{
        Red      = "`e[91m"; Green    = "`e[92m"; Yellow   = "`e[93m"
        Blue     = "`e[94m"; Magenta  = "`e[95m"; Cyan     = "`e[96m"
        White    = "`e[97m"; Gray     = "`e[37m";  DarkGray = "`e[90m"
    }
    $reset = "`e[0m"
    if ($NoNewline) {
        Write-Host "$($codes[$Color])$Text$reset" -NoNewline
    } else {
        Write-Host "$($codes[$Color])$Text$reset"
    }
}

function Show-Banner {
    Clear-Host
    $banner = @"
`e[96m
  ╔══════════════════════════════════════════════════════════════╗
  ║          PEC · AOBO Foreign Principal RBAC Tool             ║
  ║     Assign PEC-eligible roles to Foreign Group Objects      ║
  ╚══════════════════════════════════════════════════════════════╝
`e[0m
"@
    Write-Host $banner
    if ($DryRun) {
        Write-Color "  ⚠  DRY RUN MODE — no changes will be made" "Yellow"
        Write-Host ""
    }
}

function Show-Divider {
    param([string]$Title = "")
    if ($Title) {
        Write-Color "  ── $Title ──────────────────────────────────────────" "DarkGray"
    } else {
        Write-Color "  ────────────────────────────────────────────────────" "DarkGray"
    }
}

# ── TUI Menu: Single select with arrow keys ────────────────────────────────────

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Options
    )
    Write-Host ""
    Show-Divider $Title
    Write-Host ""

    $selected = 0
    $cursorTop = [Console]::CursorTop

    function Render {
        [Console]::SetCursorPosition(0, $cursorTop)
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $selected) {
                Write-Host "  `e[96m❯ $($Options[$i])`e[0m    " 
            } else {
                Write-Host "    $($Options[$i])    "
            }
        }
        Write-Color "  ↑↓ navigate · Enter select" "DarkGray"
    }

    Render
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow"   { if ($selected -gt 0) { $selected-- } }
            "DownArrow" { if ($selected -lt ($Options.Count - 1)) { $selected++ } }
            "Enter"     { 
                Write-Host ""
                return $selected 
            }
        }
        Render
    }
}

# ── TUI Menu: Multi-select with arrow keys + space to toggle ───────────────────

function Show-MultiSelectMenu {
    param(
        [string]$Title,
        [string[]]$Options,
        [switch]$AllOption
    )
    Write-Host ""
    Show-Divider $Title
    Write-Host ""

    $displayOptions = @()
    if ($AllOption) {
        $displayOptions += "★ Select All"
    }
    $displayOptions += $Options

    $selected = 0
    $checked = New-Object bool[] $displayOptions.Count
    $cursorTop = [Console]::CursorTop

    function Render {
        [Console]::SetCursorPosition(0, $cursorTop)
        for ($i = 0; $i -lt $displayOptions.Count; $i++) {
            $mark = if ($checked[$i]) { "◉" } else { "○" }
            if ($i -eq $selected) {
                Write-Host "  `e[96m❯ $mark $($displayOptions[$i])`e[0m    "
            } else {
                Write-Host "    $mark $($displayOptions[$i])    "
            }
        }
        Write-Color "  ↑↓ navigate · Space toggle · Enter confirm" "DarkGray"
    }

    Render
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow"   { if ($selected -gt 0) { $selected-- } }
            "DownArrow" { if ($selected -lt ($displayOptions.Count - 1)) { $selected++ } }
            "Spacebar"  {
                if ($AllOption -and $selected -eq 0) {
                    # Toggle all
                    $newState = -not $checked[0]
                    for ($i = 0; $i -lt $checked.Count; $i++) { $checked[$i] = $newState }
                } else {
                    $checked[$selected] = -not $checked[$selected]
                    # Uncheck "All" if individual item is unchecked
                    if ($AllOption -and -not $checked[$selected]) { $checked[0] = $false }
                }
            }
            "Enter" {
                $results = @()
                $offset = if ($AllOption) { 1 } else { 0 }
                
                if ($AllOption -and $checked[0]) {
                    # All selected
                    $results = 0..($Options.Count - 1)
                } else {
                    for ($i = $offset; $i -lt $displayOptions.Count; $i++) {
                        if ($checked[$i]) {
                            $results += ($i - $offset)
                        }
                    }
                }
                Write-Host ""
                return $results
            }
        }
        Render
    }
}

# ── TUI: Filterable multi-select for large lists ───────────────────────────────

function Show-FilterableMultiSelect {
    param(
        [string]$Title,
        [string[]]$Options
    )

    Write-Host ""
    Show-Divider $Title
    Write-Host ""
    Write-Color "  Type to filter, ↑↓ navigate, Space toggle, Enter confirm" "DarkGray"
    Write-Host ""

    $filter = ""
    $selected = 0
    $checked = @{}
    $pageSize = 15

    function Get-Filtered {
        if ([string]::IsNullOrWhiteSpace($filter)) {
            return $Options
        }
        return @($Options | Where-Object { $_ -like "*$filter*" })
    }

    $cursorTop = [Console]::CursorTop

    function Render {
        [Console]::SetCursorPosition(0, $cursorTop)
        $filtered = Get-Filtered
        
        Write-Host "  `e[93mFilter:`e[0m $filter`e[90m_`e[0m                                        "
        Write-Host "  `e[90m$($filtered.Count) of $($Options.Count) roles shown · $($checked.Count) selected`e[0m          "
        Write-Host ""

        $start = [Math]::Max(0, $selected - [Math]::Floor($pageSize / 2))
        $end = [Math]::Min($filtered.Count, $start + $pageSize)
        if ($end - $start -lt $pageSize -and $start -gt 0) {
            $start = [Math]::Max(0, $end - $pageSize)
        }

        for ($i = $start; $i -lt $end; $i++) {
            $item = $filtered[$i]
            $mark = if ($checked.ContainsKey($item)) { "◉" } else { "○" }
            if ($i -eq $selected) {
                Write-Host "  `e[96m❯ $mark $item`e[0m                                        "
            } else {
                Write-Host "    $mark $item                                        "
            }
        }
        # Clear remaining lines
        for ($j = ($end - $start); $j -lt $pageSize; $j++) {
            Write-Host "                                                          "
        }
        Write-Host ""
        Write-Color "  Space toggle · Backspace clear filter · Enter confirm" "DarkGray"
    }

    Render
    while ($true) {
        $key = [Console]::ReadKey($true)
        $filtered = Get-Filtered

        switch ($key.Key) {
            "UpArrow"    { if ($selected -gt 0) { $selected-- } }
            "DownArrow"  { if ($selected -lt ($filtered.Count - 1)) { $selected++ } }
            "Spacebar"   {
                if ($filtered.Count -gt 0 -and $selected -lt $filtered.Count) {
                    $item = $filtered[$selected]
                    if ($checked.ContainsKey($item)) {
                        $checked.Remove($item)
                    } else {
                        $checked[$item] = $true
                    }
                }
            }
            "Backspace" {
                if ($filter.Length -gt 0) {
                    $filter = $filter.Substring(0, $filter.Length - 1)
                    $selected = 0
                }
            }
            "Enter" {
                Write-Host ""
                return @($checked.Keys)
            }
            default {
                $char = $key.KeyChar
                if ($char -match '[a-zA-Z0-9 \-\(\)]') {
                    $filter += $char
                    $selected = 0
                }
            }
        }
        Render
    }
}

# ── GUID input with validation ──────────────────────────────────────────────────

function Read-GuidInput {
    param([string]$Prompt)
    while ($true) {
        Write-Host ""
        Write-Color "  $Prompt" "Cyan" -NoNewline
        $input_val = Read-Host " "
        $input_val = $input_val.Trim()
        
        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse($input_val, [ref]$guid)) {
            return $guid.ToString()
        }
        Write-Color "  ✗ Invalid GUID format. Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" "Red"
    }
}

# ── PEC-Eligible RBAC Roles ────────────────────────────────────────────────────
# Source: https://learn.microsoft.com/en-us/partner-center/billing/azure-roles-perms-pec

$PecEligibleRoles = @(
    "Owner"
    "Contributor"
    "ACRDelete"
    "ACRImageSigner"
    "ACRPull"
    "AcrPush"
    "AcrQuarantineWriter"
    "API Management Service Contributor"
    "API Management Service Operator Role"
    "Application Insights Component Contributor"
    "Application Insights Snapshot Debugger"
    "Automation Job Operator"
    "Automation Operator"
    "Automation Runbook Operator"
    "Avere Contributor"
    "Avere Operator"
    "Azure Event Hubs Data Owner"
    "Azure Event Hubs Data Receiver"
    "Azure Event Hubs Data Sender"
    "Azure Kubernetes Service Cluster Admin Role"
    "Azure Kubernetes Service Cluster User Role"
    "Azure Service Bus Data Owner"
    "Azure Service Bus Data Receiver"
    "Azure Service Bus Data Sender"
    "Azure Stack Registration Owner"
    "Backup Contributor"
    "Backup Operator"
    "BizTalk Contributor"
    "Blockchain Member Node Access (Preview)"
    "Blueprint Contributor"
    "Blueprint Operator"
    "CDN Endpoint Contributor"
    "CDN Profile Contributor"
    "Classic Network Contributor"
    "Classic Storage Account Contributor"
    "Classic Storage Account Key Operator Service Role"
    "Classic Virtual Machine Contributor"
    "Cognitive Services Contributor"
    "Cosmos DB Operator"
    "CosmosBackupOperator"
    "Cost Management Contributor"
    "Data Box Contributor"
    "Data Factory Contributor"
    "Data Lake Analytics Developer"
    "Data Purger"
    "DevTest Labs User"
    "DNS Zone Contributor"
    "DocumentDB Account Contributor"
    "Event Grid EventSubscription Contributor"
    "HDInsight Cluster Operator"
    "HDInsight Domain Services Contributor"
    "Intelligent Systems Account Contributor"
    "Key Vault Contributor"
    "Lab Creator"
    "Log Analytics Contributor"
    "Logic App Contributor"
    "Logic App Operator"
    "Managed Application Operator Role"
    "Managed Identity Contributor"
    "Managed Identity Operator"
    "Management Group Contributor"
    "Monitoring Contributor"
    "Monitoring Metrics Publisher"
    "Network Contributor"
    "New Relic APM Account Contributor"
    "Reader and Data Access"
    "Redis Cache Contributor"
    "Resource Policy Contributor"
    "Scheduler Job Collections Contributor"
    "Search Service Contributor"
    "Security Admin"
    "Security Manager (Legacy)"
    "Site Recovery Contributor"
    "Site Recovery Operator"
    "Spatial Anchors Account Contributor"
    "Spatial Anchors Account Owner"
    "SQL DB Contributor"
    "SQL Managed Instance Contributor"
    "SQL Security Manager"
    "SQL Server Contributor"
    "Storage Account Contributor"
    "Storage Account Key Operator Service Role"
    "Storage Blob Data Contributor"
    "Storage Blob Data Owner"
    "Storage Blob Delegator"
    "Storage File Data SMB Share Contributor"
    "Storage File Data SMB Share Elevated Contributor"
    "Storage Queue Data Contributor"
    "Storage Queue Data Message Processor"
    "Storage Queue Data Message Sender"
    "Support Request Contributor"
    "Traffic Manager Contributor"
    "User Access Administrator"
    "Virtual Machine Administrator Login"
    "Virtual Machine Contributor"
    "Virtual Machine User Login"
    "Web Plan Contributor"
    "Website Contributor"
)

# ── Module check ────────────────────────────────────────────────────────────────

function Assert-AzModules {
    $required = @("Az.Accounts", "Az.Resources")
    $missing = @()
    foreach ($mod in $required) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            $missing += $mod
        }
    }
    if ($missing.Count -gt 0) {
        Write-Color "  ✗ Missing required modules: $($missing -join ', ')" "Red"
        Write-Host ""
        Write-Color "  Install with: Install-Module Az -Scope CurrentUser" "Yellow"
        Write-Host ""
        exit 1
    }
    Import-Module Az.Accounts -ErrorAction SilentlyContinue
    Import-Module Az.Resources -ErrorAction SilentlyContinue
}

# ── Authentication ──────────────────────────────────────────────────────────────

function Connect-AzureIfNeeded {
    # Always force a fresh interactive browser login to avoid stale token cache issues
    Write-Color "  Clearing any cached Azure session..." "Yellow"
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Color "  Launching browser login..." "Cyan"
    Write-Host ""
    Connect-AzAccount -UseDeviceAuthentication:$false | Out-Null
    $ctx = Get-AzContext
    if ($null -eq $ctx) {
        Write-Color "  ✗ Authentication failed. Exiting." "Red"
        exit 1
    }

    Write-Color "  ✓ Authenticated" "Green"
    Write-Color "    Account : $($ctx.Account.Id)" "White"
    Write-Color "    Tenant  : $($ctx.Tenant.Id)" "White"
    Write-Host ""
    return $ctx
}

# ── Main flow ───────────────────────────────────────────────────────────────────

function Main {
    Show-Banner

    # Step 1: Module check
    Assert-AzModules

    # Step 2: Authentication
    Show-Divider "Authentication"
    $ctx = Connect-AzureIfNeeded

    # Step 3: Fetch subscriptions
    Show-Divider "Subscriptions"
    Write-Color "  Fetching subscriptions..." "Cyan"
    $subscriptions = @(Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | Sort-Object Name)

    if ($subscriptions.Count -eq 0) {
        Write-Color "  ✗ No enabled subscriptions found in this tenant." "Red"
        exit 1
    }
    Write-Color "  ✓ Found $($subscriptions.Count) enabled subscription(s)" "Green"

    # Step 4: Multi-select subscriptions
    $subLabels = $subscriptions | ForEach-Object { "$($_.Name)  `e[90m($($_.Id))`e[0m" }
    $selectedIndices = Show-MultiSelectMenu -Title "Select Subscriptions" -Options $subLabels -AllOption

    if ($selectedIndices.Count -eq 0) {
        Write-Color "  ✗ No subscriptions selected. Exiting." "Red"
        exit 1
    }

    $selectedSubs = $selectedIndices | ForEach-Object { $subscriptions[$_] }
    Write-Color "  ✓ $($selectedSubs.Count) subscription(s) selected" "Green"

    # Step 5: Foreign Principal Object ID
    Show-Divider "Foreign Principal"
    Write-Color "  Enter the Foreign Group Object ID from the partner tenant." "White"
    Write-Color "  (This is the Admin Agents group ID visible in Partner Center)" "DarkGray"
    $foreignGroupId = Read-GuidInput -Prompt "Foreign Group Object ID:"
    Write-Color "  ✓ Foreign Group ID: $foreignGroupId" "Green"

    # Step 6: PEC-eligible role selection
    $selectedRoles = Show-FilterableMultiSelect -Title "Select PEC-Eligible RBAC Role(s)" -Options @("Owner", "Contributor")

    if ($selectedRoles.Count -eq 0) {
        Write-Color "  ✗ No roles selected. Exiting." "Red"
        exit 1
    }
    Write-Color "  ✓ $($selectedRoles.Count) role(s) selected" "Green"

    # Step 7: Confirmation
    Show-Banner
    Show-Divider "Confirm Assignment"
    Write-Host ""
    Write-Color "  Foreign Group ID : $foreignGroupId" "White"
    Write-Host ""
    Write-Color "  Roles:" "White"
    foreach ($role in $selectedRoles) {
        Write-Color "    • $role" "Cyan"
    }
    Write-Host ""
    Write-Color "  Subscriptions:" "White"
    foreach ($sub in $selectedSubs) {
        Write-Color "    • $($sub.Name) `e[90m($($sub.Id))`e[0m" "Cyan"
    }
    Write-Host ""

    $totalOps = $selectedSubs.Count * $selectedRoles.Count
    if ($DryRun) {
        Write-Color "  DRY RUN: Would create $totalOps role assignment(s)" "Yellow"
    } else {
        Write-Color "  This will create $totalOps role assignment(s)." "Yellow"
    }
    Write-Host ""
    Write-Color "  Proceed? (Y/N): " "Cyan" -NoNewline
    $confirm = Read-Host
    if ($confirm -notin @("Y","y","Yes","yes")) {
        Write-Color "  Cancelled." "Yellow"
        exit 0
    }

    # Step 8: Assignment engine
    Write-Host ""
    Show-Divider "Assigning Roles"
    Write-Host ""

    $results = @()

    foreach ($sub in $selectedSubs) {
        Write-Color "  ▸ Subscription: $($sub.Name)" "White"
        
        try {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        } catch {
            Write-Color "    ✗ Failed to set context: $_" "Red"
            foreach ($role in $selectedRoles) {
                $results += [PSCustomObject]@{
                    Subscription = $sub.Name
                    SubscriptionId = $sub.Id
                    Role = $role
                    Status = "FAILED"
                    Error = "Context switch failed: $_"
                }
            }
            continue
        }

        foreach ($role in $selectedRoles) {
            $scope = "/subscriptions/$($sub.Id)"
            try {
                if ($DryRun) {
                    Write-Color "    ✓ [DRY RUN] Would assign '$role'" "Yellow"
                    $results += [PSCustomObject]@{
                        Subscription = $sub.Name
                        SubscriptionId = $sub.Id
                        Role = $role
                        Status = "DRY RUN"
                        Error = ""
                    }
                } else {
                    New-AzRoleAssignment `
                        -ObjectId $foreignGroupId `
                        -RoleDefinitionName $role `
                        -Scope $scope `
                        -ObjectType "ForeignGroup" `
                        -ErrorAction Stop | Out-Null

                    Write-Color "    ✓ Assigned '$role'" "Green"
                    $results += [PSCustomObject]@{
                        Subscription = $sub.Name
                        SubscriptionId = $sub.Id
                        Role = $role
                        Status = "SUCCESS"
                        Error = ""
                    }
                }
            } catch {
                $errMsg = $_.Exception.Message
                if ($errMsg -like "*RoleAssignmentExists*") {
                    Write-Color "    ● '$role' already assigned (skipped)" "Yellow"
                    $results += [PSCustomObject]@{
                        Subscription = $sub.Name
                        SubscriptionId = $sub.Id
                        Role = $role
                        Status = "EXISTS"
                        Error = ""
                    }
                } else {
                    Write-Color "    ✗ Failed '$role': $errMsg" "Red"
                    $results += [PSCustomObject]@{
                        Subscription = $sub.Name
                        SubscriptionId = $sub.Id
                        Role = $role
                        Status = "FAILED"
                        Error = $errMsg
                    }
                }
            }
        }
        Write-Host ""
    }

    # Step 9: Results summary
    Show-Divider "Results Summary"
    Write-Host ""

    $successCount = ($results | Where-Object { $_.Status -eq "SUCCESS" }).Count
    $existsCount  = ($results | Where-Object { $_.Status -eq "EXISTS" }).Count
    $failedCount  = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
    $dryRunCount  = ($results | Where-Object { $_.Status -eq "DRY RUN" }).Count

    if ($dryRunCount -gt 0) { Write-Color "  DRY RUN : $dryRunCount" "Yellow" }
    if ($successCount -gt 0) { Write-Color "  SUCCESS : $successCount" "Green" }
    if ($existsCount -gt 0)  { Write-Color "  EXISTS  : $existsCount" "Yellow" }
    if ($failedCount -gt 0)  { Write-Color "  FAILED  : $failedCount" "Red" }

    Write-Host ""

    if ($failedCount -gt 0) {
        Write-Color "  Failed assignments:" "Red"
        $results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
            Write-Color "    • $($_.Subscription) / $($_.Role): $($_.Error)" "Red"
        }
        Write-Host ""
    }

    Write-Color "  Done." "Green"
    Write-Host ""
}

# ── Entry point ─────────────────────────────────────────────────────────────────
Main
