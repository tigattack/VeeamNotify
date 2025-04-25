function Format-Bytes {
	<#
	.Synopsis
		Humanises data size strings.
	.DESCRIPTION
		Formats data size strings for human readability by converting the closest unit (e.g. B, KB, MB, etc.).
	.EXAMPLE
		Format-Bytes -Data 1024
	.EXAMPLE
		Format-Bytes -Data ((Get-ChildItem -Path ./ -Recurse | Measure-Object -Property Length -Sum).Sum)
	.EXAMPLE
		Get-ChildItem -Path ./ -File | Select-Object -ExpandProperty Length | Format-Bytes
	#>
	[CmdletBinding()]
	[OutputType([System.String])]
	param (
		[Parameter (Mandatory, ValueFromPipeline)]$Data
	)
	
	process {
		switch ($Data) {
			{$_ -ge 1TB } {
				$value = [math]::Round(($Data / 1TB), 2)
				return "$value TB"
			}
			{$_ -ge 1GB } {
				$value = [math]::Round(($Data / 1GB), 2)
				return "$value GB"
			}
			{$_ -ge 1MB } {
				$value = [math]::Round(($Data / 1MB), 2)
				return "$value MB"
			}
			{$_ -ge 1KB } {
				$value = [math]::Round(($Data / 1KB), 2)
				return "$value KB"
			}
			{$_ -lt 1KB} {
				$value = [math]::Round($Data, 2)
				return "$value B"
			}
			default {
				return $Data
			}
		}
	}
}
