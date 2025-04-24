function Send-Payload {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory,ParameterSetName='Notification', Position=0, ValueFromPipeline)]
		$Payload,
		[Parameter(Mandatory,ParameterSetName='Ping', Position=0)]
		[Switch]$Ping,
		[Parameter(Mandatory,ParameterSetName='Notification', Position=1)]
		[Parameter(Mandatory,ParameterSetName='Ping', Position=1, ValueFromPipeline)]
		[String]$Uri,
		$JSONPayload = $false
	)

	process {
		# Build post parameters
		if ($JSONPayload) {
			$postParams = @{
				Uri         = $Uri
				Body        = ($Payload | ConvertTo-Json -Depth 11)
				Method      = 'Post'
				ContentType = 'application/json'
				ErrorAction = 'Stop'
			}
		}
		else {
			$postParams = @{
				Body        = $Payload
				Method      = 'Post'
				ContentType = 'application/x-www-form-urlencoded'
				ErrorAction = 'Stop'
			}
		}

		try {
			# Post payload
			$request = Invoke-RestMethod @postParams

			# Return request object
			return $request
		}
		catch [System.Net.WebException] {
			Write-LogMessage -Tag 'ERROR' -Message 'Unable to send Payload. Check your Payload or network connection.'
			throw
		}
	}
}
