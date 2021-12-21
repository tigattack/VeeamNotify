function Get-UpdateStatus {

	process {
		# Get currently downloaded version of this project.
		$currentVersion = (Get-Content "$PSScriptRoot\version.txt" -Raw).Trim()

		# Get all releases from GitHub.
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		try {
			$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/VeeamDiscordNotifications/releases" -Method Get
		}
		catch {
			$versionStatusCode = $_.Exception.Response.StatusCode.value__
			Write-LogMessage -Tag 'ERROR' -Message "Failed to query GitHub for the latest version. Please check your internet connection and try again. Status code: $versionStatusCode"
			exit 1
		}

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
		If ($currentVersion -gt $latestStable) {
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

		# Return PSObject.
		return $out
	}
}
