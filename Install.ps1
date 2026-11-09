#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Preview)
# Phase 5 local launcher only. Verified release installation is planned for Phase 6.
& (Join-Path $PSScriptRoot 'Start.ps1') -Preview:$Preview
