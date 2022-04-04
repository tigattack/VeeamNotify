# Install PSSA module
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module PSScriptAnalyzer -ErrorAction Stop

# Get all relevant PowerShell files
$psFiles = Get-ChildItem -Path ./* -Include *.ps1,*.psm1 -Recurse

# Run PSSA
$issues = $null
foreach ($file in $psFiles.FullName) {
	$issues += Invoke-ScriptAnalyzer -Path $file -Recurse -Settings ./.github/scripts/pssa-settings.psd1
}

## Get results, types and report to GitHub Actions
$errors = 0
$warnings = 0
$infos = 0
$unknowns = 0

foreach ($issue in $issues) {
	switch ($issue.Severity) {
		{$_ -eq 'Error' -or $_ -eq 'ParseError'} {
			Write-Output "::error file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
			$errors++
		}
		{$_ -eq 'Warning'} {
			Write-Output "::warning file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
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

## Report summary to GitHub Actions
If ($unknowns -gt 0) {
	Write-Output "There were $erorrs errors, $warnings warnings, $infos infos, and $unknowns unknowns in total."
}
Else {
	Write-Output "There were $erorrs errors, $warnings warnings, and $infos infos in total."
}

# Exit with error if any PSSA errors
If ($errors) {
	exit 1
}
