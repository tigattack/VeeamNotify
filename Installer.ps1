#Requires -RunAsAdministrator

# Prepare variables
$rootPath = 'C:\VeeamScripts'
$project = 'VeeamDiscordNotifications'
$webhookRegex = 'https:\/\/(.*\.)?discord(app)?\.com\/api\/webhooks\/([^\/]+)\/([^\/]+)'
$mentionOnWarnExist = $mentionOnFailExist = $true

# Get latest release from GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
	$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/releases" -Method Get
}
catch {
	$versionStatusCode = $_.Exception.Response.StatusCode.value__
	Write-Warning "Failed to query GitHub for the latest version. Please check your internet connection and try again.`nStatus code: $versionStatusCode"
	exit 1
}

foreach ($i in $releases) {
	if ($i.prerelease) {
		$latestPrerelease = $i.tag_name
		break
	}
}
foreach ($i in $releases) {
	if (-not $i.prerelease) {
		$latestStable = $i.tag_name
		break
	}
}

# Query release stream
if ($releases[0].prerelease) {
	do {
		$prereleaseQuery = Read-Host -Prompt "Do you wish to install the latest prelease version $($latestPrerelease)? Y/N"
	}
	until ($prereleaseQuery -in 'Y', 'N')

	if ($prereleaseQuery -eq 'Y') {
		$release = $latestPrerelease
	}
	else {
		$release = $latestStable
	}
}
else {
	$release = $latestStable
}

# Check if this project is already installed and, if so, whether it's the latest version.
if (Test-Path $rootPath\$project) {
	$installedVersion = Get-Content -Raw "$rootPath\$project\resources\version.txt"
	If ($installedVersion -ge $release) {
		Write-Output "`nVeeamDiscordNotifications is already installed and up to date.`nExiting."
		Start-Sleep -Seconds 5
		exit
	}
	else {
		Write-Output "VeeamDiscordNotifications is already installed but it's out of date!"
		Write-Output "Please try the updater script in `"$rootPath\$project`" or download from https://github.com/tigattack/$project/releases."
	}
}

# Pull latest version of script from GitHub
$DownloadParams = @{
	Uri     = "https://github.com/tigattack/$project/releases/download/$release/$project-$release.zip"
	OutFile = "$env:TEMP\$project-$release.zip"
}
Try {
	Write-Output "`nDownloading $project $release from GitHub..."
	Invoke-WebRequest @DownloadParams
}
catch {
	$downloadStatusCode = $_.Exception.Response.StatusCode.value__
	Write-Warning "Failed to download $project $release. Please check your internet connection and try again.`nStatus code: $downloadStatusCode"
	exit 1
}

# Unblock downloaded ZIP
try {
	Write-Output 'Unblocking ZIP...'
	Unblock-File -Path "$env:TEMP\$project-$release.zip"
}
catch {
	Write-Warning 'Failed to unblock downloaded files. You will need to run the following commands manually once installation is complete:'
	Write-Output "Unblock-File -Path $rootPath\$project\*.ps*"
	Write-Output "Unblock-File -Path $rootPath\$project\resources\*.ps*"
}

# Extract release to destination path
Write-Output "Extracting files to '$rootPath'..."
Expand-Archive -Path "$env:TEMP\$project-$release.zip" -DestinationPath "$rootPath"

# Rename destination and tidy up
Write-Output "Renaming directory and tidying up...`n"
Rename-Item -Path "$rootPath\$project-$release" -NewName "$project"
Remove-Item -Path "$env:TEMP\$project-$release.zip"

# Get config
$config = Get-Content "$rootPath\$project\config\conf.json" -Raw | ConvertFrom-Json

# Check mention keys exist
if ($null -eq $config.mention_on_warning) {
	$mentionOnWarnExist = $false
}
if ($null -eq $config.mention_on_fail) {
	$mentionOnFailExist = $false
}

# Check user has webhook URL ready
do {
	$webhookPrompt = Read-Host -Prompt 'Do you have your Discord webhook URL ready? Y/N'
}
until ($webhookPrompt -in 'Y', 'N')

# Prompt user to create webhook first if not ready
If ($webhookPrompt -eq 'N') {
	Write-Output 'Please create a Discord webhook before continuing.'
	Write-Output 'Full instructions available at https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks'

	# Prompt user to launch URL
	$launchPrompt = Read-Host -Prompt 'Open URL? Y/N'
	If ($launchPrompt -eq 'Y') {
		Start-Process 'https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks'
	}

	exit
}

# Prompt user with config options
do {
	$webhookUrl = Read-Host -Prompt 'Please enter your Discord webhook URL'
	If ($webhookUrl -notmatch $webhookRegex) {
		Write-Output "`nInvalid webhook URL. Please try again."
	}
}
until ($webhookUrl -match $webhookRegex)

If ($mentionOnWarnExist) {
	Write-Output "`nDo you wish to be mentioned in Discord when a job fails or finishes with warnings?"

	do {
		$mentionPreference = Read-Host -Prompt "1 = No`n2 = On warn`n3 = On fail`n4 = On fail and on warn`nYour choice"
		If (1..4 -notcontains $mentionPreference) {
			Write-Output "`nInvalid choice. Please try again."
		}
	}
	until (1..4 -contains $mentionPreference)

	If ($mentionPreference -ne 1) {
		do {
			try {
				[Int64]$userId = Read-Host -Prompt "`nPlease enter your Discord user ID"
			}
			catch [System.Management.Automation.ArgumentTransformationMetadataException] {
				Write-Output "`nInvalid user ID. Please try again."
			}
		}
		until ($userId.ToString().Length -gt 1)
	}

	# Set config values
	$config.webhook = $webhookUrl
	Switch ($mentionPreference) {
		1 {
			$config.mention_on_fail = $false
			$config.mention_on_warning = $false
		}
		2 {
			$config.mention_on_fail = $false
			$config.mention_on_warning = $true
			$config.userId = $userId
		}
		3 {
			$config.mention_on_fail = $true
			$config.mention_on_warning = $false
			$config.userId = $userId
		}
		4 {
			$config.mention_on_fail = $true
			$config.mention_on_warning = $true
			$config.userId = $userId
		}
	}
}

elseif ($mentionOnFailExist) {
	do {
		$mentionPreference = Read-Host -Prompt 'Do you wish to be mentioned in Discord when a job finishes in a failed state? Y/N'
	}
	until ($mentionPreference -in 'Y', 'N')

	# Set config values
	If ($mentionPreference -eq 'Y') {
		do {
			$config.mention_on_fail = $true

			try {
				[Int64]$config.userId = Read-Host -Prompt "`nPlease enter your Discord user ID"
			}
			catch [System.Management.Automation.ArgumentTransformationMetadataException] {
				Write-Output "`nInvalid user ID. Please try again."
			}
		}
		until ($userId.ToString().Length -gt 1)
	}
}

# Write config
Try {
	Write-Output "`nSetting configuration..."
	ConvertTo-Json $config | Set-Content "$rootPath\$project\config\conf.json"
}
catch {
	Write-Warning "Failed to write configuration file at `"$rootPath\$project\config\conf.json`". Please open the file and complete configuration manually."
}

Write-Output "`nInstallation complete!`n"

# Run configuration deployment script.
do {
	$configPrompt = Read-Host -Prompt 'Would you like to automatically configure any of your jobs for Discord notifications? Y/N'
}
until ($configPrompt -in 'Y', 'N')

If ($configPrompt -eq 'Y') {
	Write-Output "`nRunning configuration deployment script...`n"
	& "$rootPath\$project\resources\DeployVeeamConfiguration.ps1"
}
else {
	Write-Output 'Exiting.'
	Start-Sleep -Seconds 5
	exit
}
