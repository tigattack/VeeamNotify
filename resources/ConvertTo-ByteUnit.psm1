function ConvertTo-ByteUnit {
	<#
	.Synopsis
		Converts raw numbers to byte units.
	.DESCRIPTION
		Converts raw numbers to byte units, dynamically deciding which unit (i.e. B, KB, MB, etc.) based on the input figure.
	.EXAMPLE
		ConvertTo-ByteUnit -Data 1024
	.EXAMPLE
		ConvertTo-ByteUnit -Data ((Get-ChildItem -Path ./ -Recurse | Measure-Object -Property Length -Sum).Sum)
	#>
	[CmdletBinding()]
	Param (
		[Parameter (Mandatory)]
		$Data
	)

	begin {}

	process {
		switch ($Data) {
			{$_ -ge 1TB } {
				$Value = $Data / 1TB
				[String]$Value = [math]::Round($Value,2)
				$Value += ' TB'
				break
			}
			{$_ -ge 1GB } {
				$Value = $Data / 1GB
				[String]$Value = [math]::Round($Value,2)
				$Value += ' GB'
				break
			}
			{$_ -ge 1MB } {
				$Value = $Data / 1MB
				[String]$Value = [math]::Round($Value,2)
				$Value += ' MB'
				break
			}
			{$_ -ge 1KB } {
				$Value = $Data / 1KB
				[String]$Value = [math]::Round($Value,2)
				$Value += ' KB'
				break
			}
			{$_ -lt 1KB} {
				$Value = $Data
				[String]$Value = [math]::Round($Value,2)
				$Value += ' B'
				break
			}
			default {
				$Value = $Data
				break
			}
		}
		Write-Output $Value
	}

	end {}
}
