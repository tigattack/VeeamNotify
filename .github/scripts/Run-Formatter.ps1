param (
	$Path
)

$ErrorActionPreference = 'Stop'

# Run against all files
# foreach ($file in (Get-Item *.ps1)) {
# 	try {
# 		$script = Get-Content $file -Raw

# 		If ($script.Length -eq 0) {
# 			Write-Output "Skipping empty file: $($file.Name)"
# 			continue
# 		}

# 		$scriptFormatted = Invoke-Formatter -ScriptDefinition $script -Settings ./.github/scripts/pssa-settings.psd1
# 		Set-Content -Path $file -Value $scriptFormatted -NoNewline
# 	}
# 	catch {
# 		Write-Output "Error formatting $($file.Name):"
# 		$_
# 	}
# }

try {

	$script = Get-Content -Path $Path -Raw

	If ($script.Length -eq 0) {
		Write-Output "Skipping empty file: $($Path)"
	}

	$scriptFormatted = Invoke-Formatter -ScriptDefinition $script -Settings ./.github/scripts/pssa-settings.psd1

	If ($scriptFormatted -ne $script) {
		Set-Content -Path $Path -Value $scriptFormatted -NoNewline
		Write-Output "$($Path) has been formatted."
	}
	Else {
		Write-Output "$($Path) has not been formatted (no changes required or changes could not be made non-interactively)."
	}

}
catch {
	throw "Error formatting $($Path): $($_)"
}
