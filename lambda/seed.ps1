#Requires -Modules @{ModuleName='AWS.Tools.Common';ModuleVersion='4.0.6.0'}
#Requires -Modules @{ModuleName='AWS.Tools.S3';ModuleVersion='4.0.6.0'}
#Requires -Modules @{ModuleName='AWS.Tools.SecretsManager';ModuleVersion='4.0.6.0'}
#Requires -Modules @{ModuleName='SqlServer';ModuleVersion='21.1.18221'}

$dbEndpoint = $env:DbEndpoint
$secretArn = $env:SecretArn
$scriptsBucket = $env:ScriptsBucket
$runOnDelete = [System.Convert]::ToBoolean($env:RunOnDelete)

function RetryCommand {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position=1, Mandatory=$false)]
        [int]$MaxRetries = 5,

        [Parameter(Position=2, Mandatory=$false)]
        [int]$Delay = 30
    )

    $retryAttempt = 0
    do {
        $retryAttempt++
        Write-Host "Starting attempt $retryAttempt"
        try {
            # Execute the script redirecting errors to standard output
            # due to PowerShell host's current behavior.
            # More info: https://github.com/aws/aws-lambda-dotnet/issues/697
            & {
                $ScriptBlock.Invoke()
            } 2>&1

            Write-Host "Script block completed successfully"
            return
        } catch {
            # Print the errors
            Write-Host ($Error | Format-List -Force | Out-String)

            Write-Host "Retry attempt $retryAttempt failed. $_"
            if ($retryAttempt -lt $MaxRetries) {
                # Clear the errors before next attempt
                $Error.Clear()
                # Wait and repeat
                Write-Host "Wait $Delay seconds before next attempt."
                Start-Sleep -Seconds $Delay
            } else {
                # Throw an error after $MaxRetries unsuccessful invocations.
                Write-Host "Maximum number of retry attempt ($MaxRetries) reached."
                throw $_
            }
        }
    } while ($retryAttempt -lt $MaxRetries)
}

function RunSQLScript {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$ScriptFile,
        [Parameter(Position=1, Mandatory=$false)]
        [bool]$IgnoreErrors = $false,
        [Parameter(Position=2, Mandatory=$false)]
        [int]$MaxRetries = 5,
        [Parameter(Position=3, Mandatory=$false)]
        [int]$Delay = 30
    )

    RetryCommand -ScriptBlock {
        # Download script files from S3
        $scriptPath = "/tmp/${ScriptFile}"        
        Write-Host "Downloading ${ScriptFile} from ${scriptsBucket} to ${scriptPath}"
        Read-S3Object -BucketName $scriptsBucket -Key $ScriptFile -File $scriptPath
        Write-Host "Script ${ScriptFile} downloaded"

        # Retrieving database connection details
        $secret = (Get-SECSecretValue -SecretId $secretArn -Select "SecretString" -ErrorAction Stop) | ConvertFrom-Json
        Write-Host "Database secret retrieved"

        $connectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder `
            -Property @{
                DataSource = $dbEndpoint
                UserID = $secret.username
                Password = $secret.password
            }
        $connectionString = $connectionBuilder.PSBase.ConnectionString

        # execute the cript
        $errorAction = if ($IgnoreErrors) {"Continue"} else {"Stop"}
        Write-Host "Executig script with error action: ${errorAction}"
        Invoke-Sqlcmd -ConnectionString $connectionString -InputFile $scriptPath -ErrorAction $errorAction
        if ($Error) {
            Write-Host "Some errors occurred during execution of the script, which we ignored:"
            Write-Host ($Error | Format-List -Force | Out-String)
        }

    } -MaxRetries $MaxRetries -Delay $Delay
}

# The following is a standard template for custom resource implementation.
$CFNEvent = if ($null -ne $LambdaInput.Records) {
    Write-Host 'Message received via SNS - Parsing out CloudFormation event'
    $LambdaInput.Records[0].Sns.Message
}
else {
    Write-Host 'Event received directly from CloudFormation'
    $LambdaInput
}
$body = @{
    # We'll assume success and overwrite if anything fails in line to avoid code duplication
    Status             = "SUCCESS"
    Reason             = "See the details in CloudWatch Log Stream:`n[Group] $($LambdaContext.LogGroupName)`n[Stream] $($LambdaContext.LogStreamName)"
    StackId            = $CFNEvent.StackId
    RequestId          = $CFNEvent.RequestId
    LogicalResourceId  = $CFNEvent.LogicalResourceId
}
Write-Host "Processing RequestType [$($CFNEvent.RequestType)]"
Write-Host "Resource Properties:"
Write-Host ($CFNEvent.ResourceProperties | Format-List | Out-String)

$ignoreSqlErrors = if (-not $CFNEvent.ResourceProperties.IgnoreSqlErrors) {$false} else {$true}

try {
    # If you want to return data back to CloudFormation, add the Data property to the body with the value as a hashtable. 
    # The hashtable keys will be the retrievable attributes when using Fn::GetAtt against the custom resource in your CloudFormation template:
    #    $body.Data = @{Secret = $null}

    switch ($CFNEvent.RequestType) {
        Create {
            # Add Create request code here
            Write-Host 'Running Create SQL script'
            RunSQLScript -ScriptFile "create.sql" -IgnoreErrors $ignoreSqlErrors
        }
        Delete {
            # Add Delete request code here
            if ($runOnDelete) {
                Write-Host 'Running Delete SQL script'
                RunSQLScript -ScriptFile "delete.sql" -IgnoreErrors $ignoreSqlErrors
            } else {
                Write-Host 'Noting to run on delete. Return success.'
            }           
        }
        Update {
            # Add Update request code here
            Write-Host 'SQL Seeder does not support schema updates. Return success.'
        }
    }
}
catch {
    Write-Error "Unhandled error during deployment.  $_"
    $body.Reason = "$($body.Reason). $_"
    $body.Status = "FAILED"
}

# Return body as lambda response
$payload = (ConvertTo-Json -InputObject $body -Compress -Depth 5)
$payload