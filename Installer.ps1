#Requires -RunAsAdministrator

# Prepare variables
$rootPath = 'C:\VeeamScripts'
$project = 'VeeamNotify'

Write-Output @"
#######################################
#                                     #
#        VeeamNotify Installer        #
#                                     #
#######################################`n`n
"@

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
		Write-Output "`n$project is already installed and up to date.`nExiting."
		Start-Sleep -Seconds 5
		exit
	}
	else {
		Write-Output "$project is already installed but it's out of date!"
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

# Prompt user with config options
do {
	$service = Read-Host -Prompt "Which service do you wish to send notifications to?`n1 = Discord`n2 = Slack`n3 = Teams"
}
until ($service -in '1', '2', '3')

Switch ($service) {
	1 {
		$config.service = 'Discord'
		$userIdMessage = 'Please enter your Discord user ID'
	}
	2 {
		$config.service = 'Slack'
		$userIdMessage = 'Please enter your Slack member ID'
	}
	3 {
		$config.service = 'Teams'
		$userIdMessage = 'Please enter your Teams email address'
	}
}

$config.webhook = Read-Host -Prompt 'Please enter your webhook URL'

Write-Output @"
`nDo you wish to be mentioned/tagged when a job fails or finishes with warnings?
1 = No
2 = On warn
3 = On fail
4 = On fail and on warn
"@

do {
	$mentionPreference = Read-Host -Prompt 'Your choice'
	If (1..4 -notcontains $mentionPreference) {
		Write-Output 'Invalid choice. Please try again.'
	}
}
until (1..4 -contains $mentionPreference)

If ($mentionPreference -ne 1) {
	do {
		$userId = Read-Host -Prompt "`n$userIdMessage"
	}
	until ($userId.ToString().Length -gt 1)

	If ($config.service -eq 3) {
		Write-Output "Teams also requires a name to be specified for mentions.`nIf you don't enter your name, your username (from your email address) will be used.`nIf you'd prefer this, type nothing and press enter."
		$config.teams_user_name = Read-Host -Prompt 'Please enter your name on Teams'
	}
	Else {
		$config.teams_user_name = ''
	}
}

# Set config values
Switch ($mentionPreference) {
	1 {
		$config.mention_on_fail = $false
		$config.mention_on_warning = $false
	}
	2 {
		$config.mention_on_fail = $false
		$config.mention_on_warning = $true
		$config."$($config.service)_user_id" = $userId
	}
	3 {
		$config.mention_on_fail = $true
		$config.mention_on_warning = $false
		$config."$($config.service)_user_id" = $userId
	}
	4 {
		$config.mention_on_fail = $true
		$config.mention_on_warning = $true
		$config."$($config.service)_user_id" = $userId
	}
}

# Write config
Try {
	Write-Output "`nSetting configuration..."
	ConvertTo-Json $config | Set-Content "$rootPath\$project\config\conf.json"
	Write-Output "`nConfiguration set successfully. Configuration can be found in `"$rootPath\$project\config\conf.json`"."
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
