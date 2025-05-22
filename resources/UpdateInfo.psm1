class UpdateShouldNotifyResult {
	[Parameter(Mandatory)]
	[bool]$ShouldNotify
	[string]$Message
}

function Get-UpdateShouldNotify {
	[CmdletBinding()]
	[OutputType([UpdateShouldNotifyResult])]
	param (
		[Parameter(Mandatory)]
		[PSObject]$UpdateStatus
	)

	$result = [UpdateShouldNotifyResult]@{
		ShouldNotify = $true
	}

	# If no update is available, no need to notify
	if ($UpdateStatus.Status -ne 'Behind') {
		$result.ShouldNotify = $false
		$result.Message      = 'No update available.'
		return $result
	}

	# Define marker file path
	$markerFilePath = "$PSScriptRoot\update-notification.marker"

	# Check if marker file exists
	if (Test-Path $markerFilePath) {
		$markerFile = Get-Item $markerFilePath
		$timeSinceLastNotification = (Get-Date) - $markerFile.LastWriteTime

		# If less than 24 hours have passed since last notification, don't notify
		if ($timeSinceLastNotification.TotalHours -lt 24) {
			$result.ShouldNotify = $false
			$result.Message      = "Update notification suppressed. Last notification was $($timeSinceLastNotification.TotalHours.ToString('0.00')) hours ago."

			return $result
		}
	}

	# Create or touch the marker file to indicate notification was sent
	if (Test-Path $markerFilePath) {
		(Get-Item $markerFilePath).LastWriteTime = Get-Date
	}
	else {
		New-Item -Path $markerFilePath -ItemType File -Force | Out-Null
		$result.Message = "Created update notification marker file at $markerFilePath"
	}

	return $result
}

function Get-UpdateStatus {
	# Get currently downloaded version of this project.
	$currentVersion = (Get-Content "$PSScriptRoot\version.txt" -Raw).Trim()

	# Get all releases from GitHub.
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	try {
		$releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/tigattack/VeeamNotify/releases' -Method Get
	}
	catch {
		$versionStatusCode = $_.Exception.Response.StatusCode.value__
		Write-LogMessage -Tag 'WARN' -Message "Failed to query GitHub for the latest version. Please check your internet connection and try again. Status code: $versionStatusCode"
	}

	if ($releases) {
		# Get latest stable
		foreach ($i in $releases) {
			if (-not $i.prerelease) {
				$latestStable = $i.tag_name
				break
			}
		}

		# Get latest prerelease
		foreach ($i in $releases) {
			if ($i.prerelease) {
				$latestPrerelease = $i.tag_name
				break
			}
		}

		# Determine if prerelease
		$prerelease = $false
		foreach ($i in $releases) {
			if ($i.tag_name -eq $currentVersion -and $i.prerelease) {
				$prerelease = $true
				break
			}
		}

		# Set version status
		if ($currentVersion -gt $latestStable) {
			$status = 'Ahead'
		}
		elseif ($currentVersion -lt $latestStable) {
			$status = 'Behind'
		}
		else {
			$status = 'Current'
		}

		# Create PSObject to return.
		$out = New-Object PSObject -Property @{
			CurrentVersion   = $currentVersion
			LatestStable     = $latestStable
			LatestPrerelease = $latestPrerelease
			Prerelease       = $prerelease
			Status           = $status
		}
	}
	else {
		# Create PSObject to return.
		$out = New-Object PSObject -Property @{
			CurrentVersion = $currentVersion
		}
	}

	# Return PSObject.
	return $out
}
