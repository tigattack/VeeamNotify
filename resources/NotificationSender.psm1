# Relies on functions from NotificationBuilder.psm1

class NotificationResult {
	[ValidateNotNullOrEmpty()][bool]$Success
	[string]$Message
	[hashtable]$Detail
}

function Send-Payload {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[String]$Uri,
		[Parameter(ValueFromPipeline)]
		[PSCustomObject]$Payload,
		[String]$ContentType = 'application/json',
		[String]$Method = 'Post',
		[Switch]$NoConvertJson
	)

	begin {
		# Referencing these directly in the $psVersion string didn't work, hence this.
		$psMajor = $PSVersionTable.PSVersion.Major
		$psMinor = $PSVersionTable.PSVersion.Minor
		$psVersion = "${psMajor}.${psMinor}"
	}

	process {
		if (-not $NoConvertJson) {
			$Payload = $Payload | ConvertTo-Json -Depth 11
		}

		$postParams = @{
			Uri         = $Uri
			Body        = $Payload
			Method      = $Method
			ContentType = $ContentType
			UserAgent   = "VeeamNotify; PowerShell/$psVersion"
			ErrorAction = 'Stop'
		}

		try {
			# Post payload
			$request = Invoke-RestMethod @postParams
			return [NotificationResult]@{
				Success = $true
				Message = $request
			}
		}
		catch {
			return [NotificationResult]@{
				Success = $false
				Message = 'Unable to send payload'
				Detail  = @{
					StatusCode        = $_.Exception.Response.StatusCode.value__
					StatusDescription = $_.Exception.Response.StatusDescription
					Message           = $_.ErrorDetails.Message
				}
			}
		}
	}
}

function Send-WebhookNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('Discord', 'Slack', 'Teams')]
		[string]$Service,
		[Parameter(Mandatory)]
		[System.Collections.Specialized.OrderedDictionary]$Parameters,
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	$params = New-OrderedDictionary -InputDictionary $Parameters

	# Return early if webhook is not configured or appears incorrect
	if (-not $ServiceConfig.webhook -or -not $ServiceConfig.webhook.StartsWith('http')) {
		return [NotificationResult]@{
			Success = $false
			Message = "$Service is unconfigured (invalid URL). Skipping $Service notification."
		}
	}

	# Check if user should be mentioned
	try {
		if ($params.Mention) {
			$Parameters.UserId = $ServiceConfig.user_id

			# Set username if exists (Teams specific)
			if ($Service -eq 'Teams' -and $ServiceConfig.user_name -and $ServiceConfig.user_name -ne 'Your Name') {
				$params.UserName = $ServiceConfig.user_name
			}
		}
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to add user information for mention'
			Detail  = @{
				Message = $_.Exception.Message
			}
		}
	}

	# Create payload and send notification
	try {
		$response = New-Payload -Service $Service -Parameters $params | Send-Payload -Uri $ServiceConfig.webhook
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = "Unable to send $Service notification"
			Detail  = @{
				Message = $_.Exception.Message
			}
		}
	}
}

function Send-TelegramNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[System.Collections.Specialized.OrderedDictionary]$Parameters,
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	$params = New-OrderedDictionary -InputDictionary $Parameters

	# Return early if bot token or chat ID is not configured or appears incorrect
	if ($ServiceConfig.bot_token -eq 'TelegramBotToken' -or $ServiceConfig.chat_id -eq 'TelegramChatID') {
		return [NotificationResult]@{
			Success = $false
			Message = 'Telegram is unconfigured (invalid bot_token or chat_id). Skipping Telegram notification.'
		}
	}

	# Check if user should be mentioned
	try {
		if ($params.Mention) {
			$params.UserName = $ServiceConfig.user_name
		}
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to add user information for mention'
			Detail  = @{
				Message = $_.Exception.Message
			}
		}
	}

	# Create payload and send notification
	try {
		$uri = "https://api.telegram.org/bot$($ServiceConfig.bot_token)/sendMessage"
		$params.ChatId = $ServiceConfig.chat_id
		$response = New-Payload -Service 'Telegram' -Parameters $params | Send-Payload -Uri $uri -ContentType 'application/x-www-form-urlencoded' -NoConvertJson
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to send Telegram notification'
			Detail  = @{
				Message = $_.Exception.Message
			}
		}
	}
}

function Send-HttpNotification {
	[CmdletBinding()]
	[OutputType([NotificationResult])]
	param (
		[Parameter(Mandatory)]
		[System.Collections.Specialized.OrderedDictionary]$Parameters,
		[Parameter(Mandatory)]
		[PSCustomObject]$ServiceConfig
	)

	# Return early if URL is not configured or appears incorrect
	if (-not $ServiceConfig.url -or -not $ServiceConfig.url.StartsWith('http')) {
		return [NotificationResult]@{
			Success = $false
			Message = 'HTTP service is unconfigured (invalid URL). Skipping HTTP notification.'
		}
	}

	try {
		$payloadParams = @{
			Uri    = $ServiceConfig.url
			Method = $ServiceConfig.method
		}

		if ($ServiceConfig.method.ToLower() -eq 'post') {
			$payloadParams.Payload = New-Payload -Service 'HTTP' -Parameters $Parameters
		}

		$response = Send-Payload @payloadParams
		return $response
	}
	catch {
		return [NotificationResult]@{
			Success = $false
			Message = 'Unable to send HTTP notification'
			Detail  = @{
				Message = $_.Exception.Message
			}
		}
	}
}
