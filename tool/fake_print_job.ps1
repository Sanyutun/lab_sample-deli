# Drops a fake print job into a folder so the Print Monitor can be tested
# without a printer.
#
#   .\tool\fake_print_job.ps1                      # into the default test folder
#   .\tool\fake_print_job.ps1 -Invoice 001KHL0009876 -Folder C:\temp\spool
#
# Then run the app pointed at that folder (see README) — and print the same
# file again to fire a second job, since the watcher ignores a file whose size
# has not changed.
param(
  [string]$Invoice = '001KHL0001234',
  [string]$Folder = "$env:TEMP\twok_spool_test",
  [string]$Name = 'Aye Chan',
  [string]$AgeSex = '34/F',
  [string]$Refer = 'Dr. Lin',
  [string]$Date = (Get-Date -Format 'dd/MM/yyyy HH:mm'),
  [string]$Total = '75,000 MMK'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Folder)) {
  New-Item -ItemType Directory -Path $Folder | Out-Null
}

# A fresh name each run: the watcher treats a reused name with an unchanged
# size as already handled.
$file = Join-Path $Folder ("FP{0}.SPL" -f (Get-Random -Maximum 99999))

# Receipt text as the printer pipeline would spool it, ending with the same
# CRLF line breaks the extractor's line-anchored patterns expect.
$body = @(
  'TWOK SAMPLE DELI'
  "Invoice $Invoice"
  "Name: $Name"
  "Age/Sex: $AgeSex"
  "Refer: $Refer"
  "Date: $Date"
  "Total Amount: $Total"
  ''
) -join "`r`n"

# UTF-16LE with BOM, which is what the Windows print pipeline spools.
$encoding = [System.Text.Encoding]::Unicode
$bytes = $encoding.GetPreamble() + $encoding.GetBytes($body)
[System.IO.File]::WriteAllBytes($file, $bytes)

Write-Host "Wrote $file"
Write-Host "Invoice: $Invoice  Name: $Name  Total: $Total"
