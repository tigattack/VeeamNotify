function New-OrderedDictionary {
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[System.Collections.Specialized.OrderedDictionary]$InputDictionary
	)

	process {
		$clone = [ordered]@{}
		$InputDictionary.GetEnumerator() | ForEach-Object {
			$clone.Add($_.Key, $_.Value)
		}
		return [System.Collections.Specialized.OrderedDictionary]$clone
	}
}
