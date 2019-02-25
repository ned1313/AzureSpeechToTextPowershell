# AzureSpeechToTextPowershell
PowerShell Scripts for Azure Speech to Text API

## Description
This set of scripts is intended to work with the batch functionality of the Azure [Speech Services API](https://westus.cris.ai/swagger/ui/index).  There are a few underlying assumptions:

-  You have the files in a supported format and stored in an Azure blob container
-  You have already created an Azure Cognitive Services Speech resource
-  You are logged into Azure using the *Add-AzureRMAccount* command
-  The content you want to transcribe is longer in format, so batch makes sense to use

My particular use case was to transcribe podcast episodes for a podcast I run.  The eventual workflow would be to upload a new podcast to the blob container and trigger a set of events to have the mp3 transcribed and the results emailed to me.  

## The Scripts
This is a work in progress.  I've broken things out into separate functions.  I may turn these into classes and methods at some point down the road.  I also need to add a lot more comments and error checking, as well as input validation and Pester tests.  For the moment though, it is at MVP for my usage.

