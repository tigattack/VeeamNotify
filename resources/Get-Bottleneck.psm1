# Function to get a session's bottleneck from the session logs
# See https://github.com/tigattack/VeeamNotify/issues/19 for more details.
Function Get-Bottleneck {
	param(
		$Logger
	)

	$bottleneck = ($Logger.GetLog() |
			Select-Object -ExpandProperty UpdatedRecords |
			Where-Object {$_.Title -match 'Primary bottleneck:.*'} |
			Select-Object -ExpandProperty Title) -replace 'Primary bottleneck:',''

	If ($bottleneck.Length -eq 0) {
		$bottleneck = 'Undetermined'
	}
	Else {
		$bottleneck = $bottleneck.Trim()
	}

	return $bottleneck
}
