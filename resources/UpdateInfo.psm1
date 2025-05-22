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
		Message      = ''
	}

	# If no update is available, no need to notify
	if ($UpdateStatus.Status -ne 'Behind') {
		$result.ShouldNotify = $false
		$result.Message      = 'No update available.'
		return $result
	}

	# Define marker file path
	$markerFilePath = "$PSScriptRoot\update-notification.marker"

	$currentVersion = $UpdateStatus.CurrentVersion

	# Check if marker file exists
	if (Test-Path $markerFilePath) {
		$versionChanged = $false
		$markerVersion = Get-Content -Path $markerFilePath -Raw -ErrorAction SilentlyContinue
		if ($null -ne $markerVersion) {
			# Trim version and compare with current version
			$markerVersion = $markerVersion.Trim()
			$versionChanged = $markerVersion -ne $currentVersion
		}

		$markerFile = Get-Item $markerFilePath
		$timeSinceLastNotification = (Get-Date) - $markerFile.LastWriteTime

		# If version has changed, always notify regardless of time
		if ($versionChanged) {
			$result.Message = "Version changed from $markerVersion to $currentVersion since last notification. Proceeding to notify."
			# Update the marker file with current version
			$currentVersion | Out-File -FilePath $markerFilePath -Force -NoNewline
			return $result
		}

		# If less than 24 hours have passed since last notification for the same version, don't notify
		if ($timeSinceLastNotification.TotalHours -lt 24) {
			$result.ShouldNotify = $false
			$result.Message      = "Update notification suppressed. Last notification was $($timeSinceLastNotification.TotalHours.ToString('0.00')) hours ago."
			return $result
		}
		# If more than 24 hours have passed, proceed to notify and update the marker file contents
		else {
			$result.Message = "Update notification marker file found. Last notification was $($timeSinceLastNotification.TotalHours.ToString('0.00')) hours ago. Proceeding to notify."
			# Update the marker file with current version - Also updates the file's modtime as a side effect.
			$currentVersion | Out-File -FilePath $markerFilePath -Force -NoNewline
		}
	}
	else {
		# Create the marker file to indicate notification was sent and store current version
		$currentVersion | Out-File -FilePath $markerFilePath -Force -NoNewline
		$result.Message = "Created update notification marker file at $markerFilePath with version $currentVersion"
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
