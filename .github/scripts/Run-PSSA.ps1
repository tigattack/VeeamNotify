param (
	[array]$Files
)

# init variables
$errors = $warnings = $infos = $unknowns = 0

# Define function to handle GitHub Actions output
function Out-Severity {
	param(
		$InputObject
	)

	foreach ($i in $InputObject) {
		Switch ($i.Severity) {
			{$_ -eq 'Error' -or $_ -eq 'ParseError'} {
				Write-Output "::error file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
				$script:errors++
			}
			{$_ -eq 'Warning'} {
				Write-Output "::error file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
				$script:warnings++
			}
			{$_ -eq 'Information'} {
				Write-Output "::warning file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
				$script:infos++
			}
			Default {
				Write-Output "::debug file=$($i.ScriptName),line=$($i.Line),col=$($i.Column)::$($i.RuleName) - $($i.Message)"
				$script:unknowns++
			}
		}
	}
}

$ErrorActionPreference = 'Stop'

# Run PSSA
foreach ($file in $Files) {
	try {
		Write-Output "$($file) is being analysed..."
		Invoke-ScriptAnalyzer -Path $file -Settings ./.github/scripts/pssa-settings.psd1 -OutVariable analysis | Out-Null
		Format-List -InputObject $analysis

		If ($analysis) {
			Write-Output 'Determining and reporting severity of analysis results...'
			Out-Severity -InputObject $analysis
		}

		Write-Output "$($file) was analysed; it has $($analysis.Count) issues."
	}
	catch {
		Write-Output "Error analysing $($file):"
		exit 1
	}
}

Write-Output "`nNOTE: In an effort to better enforce good practices, this script is configured to report analysis results as follows:"
Write-Output 'Error and warning messages as errors and informational messages as warnings.'

# Report true results
If ($unknowns -gt 0) {
	Write-Output "`nTrue result: $errors errors, $warnings warnings, $infos infos, and $unknowns unknowns in total."
}
Else {
	Write-Output `n"True result: $errors errors, $warnings warnings, and $infos infos in total."
}

# Exit with error if any PSSA errors
If ($errors -gt 0 -or $warnings -gt 0) {
	exit 1
}
