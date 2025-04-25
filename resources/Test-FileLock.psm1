# I believe the source of the original implementation of this function (since changed) was:
# https://mcpmag.com/articles/2018/07/10/check-for-locked-file-using-powershell.aspx
# Written by Boe Prox, Microsoft MVP.
function Test-FileLock {
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('FullName', 'PSPath')]
		[string]$Path
	)
	process {
		# Ensure this is a full path
		$Path = Convert-Path $Path
		# Verify that this is a file and not a directory
		if ([System.IO.File]::Exists($Path)) {
			try {
				$FileStream = [System.IO.File]::Open($Path, 'Open', 'Write')
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
