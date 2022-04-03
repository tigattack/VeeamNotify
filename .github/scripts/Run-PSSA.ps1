param (
	[array]$Files
)

$ErrorActionPreference = 'Stop'

# Run PSSA
$issues = foreach ($file in $Files) {
	try {
		Invoke-ScriptAnalyzer -Path $file -Recurse -Settings ./.github/scripts/pssa-settings.psd1
		Write-Host "$($file) was analysed"
	}
	catch {
		Write-Host "Error analysing $($file): $_.Exception.Message"
	}
}

# init variables
$errors = $warnings = $infos = $unknowns = 0

# Get results, types and report to GitHub Actions
foreach ($i in $issues) {
	switch ($i.Severity) {
		{$_ -eq 'Error' -or $_ -eq 'ParseError'} {
			Write-Output "::error file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
			$errors++
		}
		{$_ -eq 'Warning'} {
			Write-Output "::error file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
			$warnings++
		}
		{$_ -eq 'Information'} {
			Write-Output "::warning file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
			$infos++
		}
		Default {
			Write-Output "::debug file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
			$unknowns++
		}
	}
}

# Report summary to GitHub Actions
If ($unknowns -gt 0) {
	Write-Output "There were $errors errors, $warnings warnings, $infos infos, and $unknowns unknowns in total."
}
Else {
	Write-Output "There were $errors errors, $warnings warnings, and $infos infos in total."
}

# Exit with error if any PSSA errors
If ($errors -gt 0 -or $warnings -gt 0) {
	exit 1
}
