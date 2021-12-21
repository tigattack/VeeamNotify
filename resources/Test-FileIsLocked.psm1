Function Test-FileIsLocked {
	[cmdletbinding()]
	Param (
		[parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
		[Alias('FullName','PSPath')]
		[string[]]$Path
	)
	Process {
		ForEach ($Item in $Path) {
			#Ensure this is a full path
			$Item = Convert-Path $Item
			#Verify that this is a file and not a directory
			If ([System.IO.File]::Exists($Item)) {
				Try {
					$FileStream = [System.IO.File]::Open($Item,'Open','Write')
					$FileStream.Close()
					$FileStream.Dispose()
					$IsLocked = $False
				}
				Catch [System.UnauthorizedAccessException] {
					$IsLocked = 'AccessDenied'
				}
				Catch {
					$IsLocked = $True
				}
				[pscustomobject]@{
					File = $Item
					IsLocked = $IsLocked
				}
			}
		}
	}
}
