class JsonValidationResult {
	[Parameter(Mandatory)]
	[bool]$IsValid
	[string]$Message
}

# Thanks to Mathias R. Jessen for the foundations of this function
# https://stackoverflow.com/a/75759006/5209106
function Test-JsonValid {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$JsonPath,
		[Parameter(Mandatory)]
		[string]$SchemaPath
	)

	$NewtonsoftJsonPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'lib\Newtonsoft.Json.dll')
	$NewtonsoftJsonSchemaPath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'lib\Newtonsoft.Json.Schema.dll')

	Add-Type -Path $NewtonsoftJsonPath
	Add-Type -Path $NewtonsoftJsonSchemaPath

	if (-not (Test-Path -Path $JsonPath)) {
		throw "JSON file not found: $JsonPath"
	}
	if (-not (Test-Path -Path $SchemaPath)) {
		throw "Schema file not found: $SchemaPath"
	}

	$jsonStr = Get-Content -Path $JsonPath -Raw
	$schemaStr = Get-Content -Path $SchemaPath -Raw

	try {
		# Create a reader for the JSON string
		$stringReader = New-Object System.IO.StringReader($jsonStr)
		$jsonReader = New-Object Newtonsoft.Json.JsonTextReader($stringReader)

		$schemaObj = [Newtonsoft.Json.Schema.JSchema]::Parse($schemaStr)

		$validator = New-Object Newtonsoft.Json.Schema.JSchemaValidatingReader($jsonReader)
		$validator.Schema = $schemaObj

		$serializer = New-Object Newtonsoft.Json.JsonSerializer

		# Attempt to deserialize input JSON via validator
		$null = $serializer.Deserialize($validator)

		# Schema validation succeeded if we get this far
		return [JsonValidationResult]@{
			IsValid = $true
			Message = 'JSON validation succeeded.'
		}
	}
	catch [Newtonsoft.Json.Schema.JSchemaException] {
		# Schema validation failed
		return [JsonValidationResult]@{
			IsValid = $false
			Message = $_.Exception.Message
		}
	}
	catch {
		# Other error occurred
		return [JsonValidationResult]@{
			IsValid = $false
			Message = "Unexpected error: $($_.Exception.Message)"
		}
	}
	finally {
		# Clean up resources
		if ($null -ne $stringReader) { $stringReader.Dispose() }
		if ($null -ne $jsonReader) { $jsonReader.Dispose() }
		if ($null -ne $validator) { $validator.Dispose() }
	}
}
