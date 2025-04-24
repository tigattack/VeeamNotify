function Test-FileLock {
	[cmdletbinding()]
	param (
		[parameter(Mandatory = $True, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
		[Alias('FullName', 'PSPath')]
		[string[]]$Path
	)
	process {
		foreach ($Item in $Path) {
			#Ensure this is a full path
			$Item = Convert-Path $Item
			#Verify that this is a file and not a directory
			if ([System.IO.File]::Exists($Item)) {
				try {
					$FileStream = [System.IO.File]::Open($Item, 'Open', 'Write')
					$FileStream.Close()
					$FileStream.Dispose()
					$IsLocked = $False
				}
				catch [System.UnauthorizedAccessException] {
					$IsLocked = 'AccessDenied'
				}
				catch {
					$IsLocked = $True
				}
				[pscustomobject]@{
					File     = $Item
					IsLocked = $IsLocked
				}
			}
		}
	}
}
