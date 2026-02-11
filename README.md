# Azure PEC AOBO Tool
This repository captures the `PEC-AOBO.ps1` script that MSPs can run to assign PEC-eligible RBAC roles to a foreign principal (ForeignGroup) in customer tenants via Admin On Behalf Of (AOBO).

## Features
- Interactive ANSI-based TUI with banners, dividers, and guided prompts.
- Subscription multi-select menu with “select all” support and a filterable, multi-role picker.
- Validates required Az modules, forces a fresh login, and summarizes success/existing/failure counts.
- Supports a `-DryRun` switch to preview assignments without touching resources.

## Requirements
- PowerShell 7+ (or Windows PowerShell) with [Az.Accounts](https://www.powershellgallery.com/packages/Az.Accounts) and [Az.Resources](https://www.powershellgallery.com/packages/Az.Resources) modules installed (`Install-Module Az -Scope CurrentUser`).
- A partner identity with permission to perform AOBO assignments and the Foreign Group Object ID from Partner Center.

## Usage
1. Open PowerShell and authenticate through the browser prompt.
2. Run:
   ```powershell
   pwsh ./PEC-AOBO.ps1
   ```
3. Select customer subscriptions, enter the Foreign Group ID, choose PEC-eligible roles, and confirm the bulk assignment.

To preview the actions before they run, append the `-DryRun` switch:
```powershell
pwsh ./PEC-AOBO.ps1 -DryRun
```

## Notes
- The role picker is scoped to PEC-eligible assignments defined toward the top of the script (the source list is the official Partner Center guidance).
- Assignments run per selected subscription, and the summary at the end surfaces results or failures for each role/subscription combination.
