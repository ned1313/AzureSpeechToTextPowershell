Function Get-AzSSBatchResults {
    param (
        [string] $subscriptionKey,
        [Parameter(
            ParameterSetName='ById',
            Mandatory
        )]
        [string] $serviceRegion = "westus",
        [Parameter(
            ParameterSetName='ById',
            Mandatory
        )]
        [string] $id,
        [Parameter(
            ParameterSetName='ByUri',
            Mandatory
        )]
        [string] $uri,
        [string] $filepath = $script:HOME
    )

    #Create header for initial request and add the Subscription Key
    $header = @{}
    $header.Add("Ocp-Apim-Subscription-Key",$subscriptionKey)

    #Get the blob batch status if it exists
    try {
        if($PSCmdlet.ParameterSetName -eq "ById"){
            $batchStatus = Get-AzSSBatchStatus -subscriptionKey $subscriptionKey -serviceRegion $serviceRegion -id $id
        }
        else{
            $batchStatus = Get-AzSSBatchStatus -subscriptionKey $subscriptionKey -uri $uri
        }

        #Make sure the status of the transcription request is succeeded
        if($batchStatus.status -eq "Succeeded"){
            #Get results file for each channel and write out to destination
            Invoke-WebRequest -UseBasicParsing -Uri $batchStatus.resultsUrls.channel_0 -OutFile "$filepath\$($batchStatus.name)_$($batchStatus.id)_channel_0.json"
            Invoke-WebRequest -UseBasicParsing -Uri $batchStatus.resultsUrls.channel_1 -OutFile "$filepath\$($batchStatus.name)_$($batchStatus.id)_channel_1.json"
        }
        else{
            throw "Status of transcription is $($batchStatus.status).  Status must be Succeeded to retrieve results."
        }
    }
    catch{
        Write-error -Message $_.Exception.Message
    }
}

Function Get-AzSSBatchStatus {
        param (
        [string] $subscriptionKey,
        [Parameter(
            ParameterSetName='ById',
            Mandatory
        )]
        [string] $serviceRegion = "westus",
        [Parameter(
            ParameterSetName='ById',
            Mandatory
        )]
        [string] $id,
        [Parameter(
            ParameterSetName='ByUri',
            Mandatory
        )]
        [string] $uri

    )

    #Create header for initial request and add the Subscription Key
    $header = @{}
    $header.Add("Ocp-Apim-Subscription-Key",$subscriptionKey)

    if($PSCmdlet.ParameterSetName -eq "ById"){
        #Construct the API endpoint
        $apiSuffix = ".cris.ai"
        $uri = "https://$serviceRegion$apiSuffix/api/speechtotext/v2.0/Transcriptions/$id"
    }

    #Get the blob batch status if it exists
    try {
            #Query for the submitted ID
            $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers $header

        if($response.StatusCode -ne "200"){
            throw "Attempted to retrieve status for $uri, received HTTP code of $($response.StatusCode) $($response.StatusDescription)"
        }
        else{
            #Convert From Json and return the full response
            $json = $response | ConvertFrom-Json

            return $json
        }
    }
    catch{
        Write-error -Message $_.Exception.Message
    }

}

Function New-AzSSBatchRequest {
    param (
        [string] $subscriptionKey,
        [string] $serviceRegion = "westus",
        [string] $blobSAS,
        [string[]] $models = @(),
        [string] $locale = "en-US",
        [string] $transcriptionName,
        [string] $transcriptionDesc,
        [string] $profanityFilterMode = "Masked",
        [string] $PunctuationMode = "Automatic",
        [string] $addWordLevelTimestamps = "True"
    )

    #Create header for initial request and add the Subscription Key
    $header = @{}
    $header.Add("Ocp-Apim-Subscription-Key",$subscriptionKey)

    #Construct the API endpoint
    $apiSuffix = ".cris.ai"
    $fullURI = "https://$serviceRegion$apiSuffix/api/speechtotext/v2.0/Transcriptions/"

    #Construct the body of the request
    $body = @{
        recordingsUrl = $blobSAS
        models = $models
        locale = $locale
        name = $transcriptionName
        description = $transcriptionDesc
        properties = @{
            ProfanityFilterMode = $profanityFilterMode
            PunctuationMode = $PunctuationMode
            AddWordLevelTimestamps = $addWordLevelTimestamps
        }
    }

    #Create the request
    try {
        $response = Invoke-WebRequest -Method POST -Uri $fullURI -Headers $header -Body $($body | ConvertTo-Json) -ContentType "application/json"

        if($response.StatusCode -ne "202"){
            throw "Attempted to create transcription for $transcriptionName, received HTTP code of $($response.StatusCode) $($response.StatusDescription)"
        }
        else{
            #Return the ID of the transcription request
            Return $response.Headers.Location
        }
    }
    catch {
        Write-Error -Message $_.Exception.Message
    }

}

Function Remove-AzSSBatchRequest {
    param (
        [string] $subscriptionKey,
        [string] $requestURL
    )

    #Create header for initial request and add the Subscription Key
    $header = @{}
    $header.Add("Ocp-Apim-Subscription-Key",$subscriptionKey)

    #Create the request
    try {
        $response = Invoke-WebRequest -Method DELETE -Uri $requestURL -Headers $header

        if($response.StatusCode -ne "204"){
            throw "Attempted to create transcription for $transcriptionName, received HTTP code of $($response.StatusCode) $($response.StatusDescription)"
        }
        else{
            #Convert to JSON
            $json = $response | ConvertFrom-Json
            return $json
        }
    }
    catch {
        Write-Error -Message $_.Exception.Message
    }

}


Function New-AzSSMultiBatchRequest {
    param(
        [string] $storageAccountName,
        [string] $resourceGroupName,
        [string] $containerName,
        [string] $subscriptionKey,
        [string] $serviceRegion = "westus",
        [string[]] $models = @(),
        [string] $locale = "en-US",
        [string] $profanityFilterMode = "Masked",
        [string] $PunctuationMode = "Automatic",
        [string] $addWordLevelTimestamps = "True",
        [string] $resultsPath = $script:HOME,
        [int] $updateTimer = 30
    )

    #Get SAS tokens for all the blobs
    $tokens = New-AzStorageSASTokenAllBlobs -storageAccountName $storageAccountName -resourceGroupName $resourceGroupName -containerName $containerName

    #For each blob start a new batch run
    $ids = @{}
    foreach($key in $tokens.Keys){
        $id = New-AzSSBatchRequest -subscriptionKey $subscriptionKey -serviceRegion $serviceRegion -blobSAS $tokens[$key] -transcriptionName $key -transcriptionDesc "$key started at $(Get-Date)"
        $ids.Add($id,$key)
    }

    #Now watch the batch runs and output results to JSON as needed
    $runningCount = $ids.Count
    $succeededCount = 0
    $failedCount = 0
    $waitingCount = 0
    $failedIds = @{}

    do{
        Write-Output "$runningCount items running, $succeededCount completed, $failedCount failed"
        $keys = $ids.Keys
        $keysToRemove = @()
        foreach($id in $keys){
            try{
            $status = (Get-AzSSBatchStatus -subscriptionKey $subscriptionKey -uri $id).status
            if($status -eq "Running"){
                Write-Output "Transctiption id $id is still running"
            }
            elseif($status -eq "Succeeded") {
                Write-Output "Transctiption id $id succeeded"
                Write-Output "Writing json for $id to $resultsPath"
                Get-AzSSBatchResults -subscriptionKey $subscriptionKey -uri $id -filepath $resultsPath
                $keysToRemove += $id
                $succeededCount++
                $runningCount--
            }
            elseif($status -eq "NotStarted"){
                Write-Output "Transctiption id $id has not started yet"

            }
            elseif($status -eq "Failed"){
                Write-Output "Transctiption id $id failed"
                $failedIds.Add($id,$ids[$id])
                $keysToRemove += $id
                $failedCount++
                $runningCount--
            }
        }
        catch {
            Write-Output "Error on $id is $($_.Exception.Message)"
            $keysToRemove += $id
            $failedCount++
            $runningCount--
        }
        }
        foreach($id in $keysToRemove){
            $ids.Remove($id)
        }
        Wait-Event -Timeout $updateTimer

    }while($runningCount -gt 0)
}

Function New-AzStorageSASTokenAllBlobs {
    param(
        [string] $storageAccountName,
        [string] $resourceGroupName,
        [string] $containerName
    )

    $sa = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $key = Get-AzureRmStorageAccountKey -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName
    $ctx = New-AzureStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey $key[0].Value
    $container = Get-AzureStorageContainer -Name $containerName -Context $ctx
    $blobs = Get-AzureStorageBlob -Container $container.Name -Context $ctx

    $tokens = @{}
    foreach($blob in $blobs){
        $token = New-AzureStorageBlobSASToken -CloudBlob $blob.ICloudBlob -Context $blob.Context -Permission r -FullUri
        $tokens.Add($blob.Name, $token)
    }

    return $tokens
}