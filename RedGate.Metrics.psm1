#requires -version 4

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# For each file in Public/, publish a function with the same name
Get-ChildItem "$PSScriptRoot\Public\" -Filter *.ps1 |
    ForEach-Object {
      . $_.FullName
      Export-ModuleMember -Function $_.BaseName
    }

Export-ModuleMember -Variable PaketExe

# For debug purposes, uncomment this to export all functions of this module.
# Export-ModuleMember -Function *
