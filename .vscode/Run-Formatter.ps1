$ErrorActionPreference = 'Stop'

# Get all relevant PowerShell files
$psFiles = Get-ChildItem -Path ./* -Include *.ps1,*.psm1 -Recurse

# Run formatter
foreach ($file in $psFiles) {
	try {
		$script = Get-Content $file -Raw

		If ($script.Length -eq 0) {
			Write-Output "Skipping empty file: $($file.Name)"
			continue
		}

		$scriptFormatted = Invoke-Formatter -ScriptDefinition $script -Settings .\.github\scripts\pssa-settings.psd1
		Set-Content -Path $file -Value $scriptFormatted -NoNewline
	}
	catch {
		Write-Output "Error formatting $($file.Name):"
		$_
	}
}
