# Settings for PSScriptAnalyzer invocation.
@{
	ExcludeRules = @(
		'PSReviewUnusedParameter', # Required due to PowerShell/PSScriptAnalyzer#1472.
		'PSAvoidLongLines'
	)
	Rules = @{
		PSAvoidUsingDoubleQuotesForConstantString = @{
			Enable = $true
		}
		PSAvoidUsingPositionalParameters = @{
			Enable = $true
		}
		PSUseCompatibleCommands = @{
			Enable = $true
			# PowerShell platforms we want to check compatibility with
			TargetProfiles = @(
				'win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework', # PowerShell 5.1 on Windows Server 2016
				'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework', # PowerShell 5.1 on Windows Server 2019
				'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'#, # PowerShell 5.1 on Windows 10
				#'win-8_x64_10.0.14393.0_6.2.4_x64_4.0.30319.42000_core', # PowerShell 6.2 on Windows Server 2016
				#'win-8_x64_10.0.17763.0_6.2.4_x64_4.0.30319.42000_core', # PowerShell 6.2 on Windows Server 2019
				#'win-4_x64_10.0.18362.0_6.2.4_x64_4.0.30319.42000_core', # PowerShell 6.2 on Windows 10
				#'win-8_x64_10.0.14393.0_7.0.0_x64_3.1.2_core', # PowerShell 7.0 on Windows Server 2016
				#'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core', # PowerShell 7.0 on Server 2019
				#'win-4_x64_10.0.18362.0_7.0.0_x64_3.1.2_core' # PowerShell 7.0 on Windows 10
			)
		}
		PSUseCompatibleSyntax = @{
			Enable = $true
			# PowerShell versions we want to check compatibility with
			TargetVersions = @(
				'5.1'#,
				#'6.2',
				#'7.1'
			)
		}
		PSPlaceCloseBrace = @{
			Enable = $true
			NoEmptyLineBefore = $false
			IgnoreOneLineBlock = $true
			NewLineAfter = $true
		}
		PSPlaceOpenBrace = @{
			Enable = $true
			OnSameLine = $true
			NewLineAfter = $true
			IgnoreOneLineBlock = $true
		}
		PSUseConsistentIndentation = @{
			Enable = $true
			IndentationSize = 4
			PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
			Kind = 'tab'
		}
		PSAvoidLongLines = @{
			Enable = $true
			MaximumLineLength = 155
		}
	}
}
