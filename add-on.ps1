#!/usr/bin/env pwsh

# To run this file in Linux first make sure you have PowerShell installed
# then either chmod +x or use pwsh <file> command

# To run this file on Windows create a bat/cmd file with the same name as this file
# and the following contents (Without the comment mark) then run THE NEW FILE
# @Powershell -NoProfile -ExecutionPolicy Unrestricted -File "%~dpn0.ps1"

Set-StrictMode -Version 2.0
Add-Type -Assembly System.Web

Write-Host "[Stremio add-on Predavatel.com] Please Wait..." -f "yellow"

$scrapeURL = "http://predavatel.com/bg/live/"
$idPrefix = "predavatel"

$MANIFEST = @{
	id          = "com.predavatel.radio"
	version     = "1.0.0"
	name        = "Радио предавател"
	description = "Радио програми от predavatel.com"
	icon        = "http://www.predavatel.com/images/menu_predavatel.png"
	types       = @("channel")
	catalogs    = @(
		@{
			type = "channel"
			id   = "top"
		}
	)
	resources   = @(
		"catalog"
		"stream"
		"meta"
	)
	idPrefixes  = @($idPrefix)
}

Write-Host "Fetching data from $scrapeURL..."

$res = Invoke-WebRequest $scrapeURL

function ReEncode {
	param(
		[Parameter(Mandatory, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[String]$From
	)
	# Charsets from https://docs.microsoft.com/en-us/dotnet/api/system.text.encoding?view=netframework-4.7.2
	# Decoding Problem solved by https://2cyr.com/decode/?lang=bg
	$utf8 = [System.Text.Encoding]::GetEncoding(65001)
	$iso88591 = [System.Text.Encoding]::GetEncoding(28591) #ISO 8859-1 ,Latin-1
	$utf8.GetString( $iso88591.GetBytes([System.Web.HttpUtility]::HtmlDecode($From)))
}

# Populate catalog and streams once on startup
# This doesn't change so oftern
# Restart the script to update the sources

[Hashtable]$STREAMS = @{}

$CATALOG = $res.parsedHtml.getElementsByClassName('fix') | ForEach-Object {$channelId = 0 } {
	$rows = $_.getElementsByTagName('TR')
	$id = $idPrefix + (++$channelId)
	$categoryName = ReEncode $rows[0].firstChild.innerHTML
	@{
		genres      = @()
		poster      = 'data:image/svg+xml;base64,'+[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="200" height="400" viewBox="0 0 200 400"><rect id="rect1" width="100%" height="100%" fill="#3a497d"/><foreignObject x="0" y="233" width="100%" height="133"><p xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;color:#fff;font-family:LatoLight,Arial,Helvetica,sans-serif;font-size:24px;padding: 0 .3em;">'+$categoryName+'</p></foreignObject></svg>'))
		logo        = 'data:image/svg+xml;base64,'+[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="400" height="200" viewBox="0 0 400 200"><foreignObject x="0" y="0" width="100%" height="200"><p xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;color:#fff;font-family:LatoLight,Arial,Helvetica,sans-serif;font-size:30px;padding: 0 .3em;">'+$categoryName+'</p></foreignObject></svg>'))
		posterShape = "landscape"
		type        = "channel"
		id          = $id
		name        = $categoryName
		description = $categoryName
		radios      = $rows | Where-Object {$_.getElementsByTagName('B')} | ForEach-Object {$radioId = 0 } {
			$link = $_.firstChild.firstChild.firstChild
			$rId = $id + "_" + (++$radioId)
			$STREAMS[$rId] = @($_.childNodes[1].getElementsByTagName('A') | ForEach-Object {
				@{
					id    = $rId
					title = ReEncode $_.textContent.trim()
					url   = $_.href
				}
			})

			@{
				id        = $rId
				title     = ReEncode $link.textContent.trim()
				thumbnail = [Uri]::new([Uri]$scrapeURL, [String]$link.firstChild.src.Remove(0, 6)).AbsoluteUri
			}
		}
	}
}

# Http Server
$http = [System.Net.HttpListener]::new()

# Hostname and port to listen on
$http.Prefixes.Add("http://127.0.0.1:8080/")

# Start the Http Server
$http.Start()

# Log ready message to terminal
if ($http.IsListening) {
	Write-Host "HTTP Server Ready!" -f 'black' -b 'green'
	Write-Host "Tha add-on's manifest is located at $($http.Prefixes)manifest.json" -f 'yellow'
}

function Write-Response {
	param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[Int]$status,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[String]$type,

		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[String]$data
	)
	$buffer = [System.Text.Encoding]::UTF8.GetBytes($data)

	$res.StatusCode = $status
	$res.Headers.Add("Content-Type", $type)
	$res.Headers.Add("Access-Control-Allow-Origin", "*")
	$res.Headers.Add("Access-Control-Allow-Headers", "*")
	$res.ContentLength64 = $buffer.Length
	$res.OutputStream.Write($buffer, 0, $buffer.Length) #stream to broswer
	$res.OutputStream.Close() # close the response
}

function Write-JSON {
	param(
		[Parameter(Mandatory, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[Object]$data
	)

	Write-Response 200 "application/json" (ConvertTo-Json $data -Depth 4)
}

function Write-404 {
	Write-Response 404 "text/plain" "404 Not Found"
}

# INFINTE LOOP
# Used to listen for requests
while ($http.IsListening) {
	$context = $http.GetContext()
	$req = $context.Request
	$res = $context.Response

	$path = [System.Web.HttpUtility]::UrlDecode($req.RawUrl)

	# We can log the request to the terminal
	Write-Host ""
	Write-Host "$($req.Url.OriginalString)"
	Write-Host "$($req.HttpMethod) $($path)" -f 'green'

	# Get Requests only
	if ($req.HttpMethod -ne 'GET') {
		Write-404
		continue
	}

	switch -regex ($path) {
		'^/([?].*|)$' {
			Write-Response 200 "text/html" "<a href='$($http.Prefixes)manifest.json'>Install this add-on</a>"
			break
		}

		'^/manifest.json([?].*|)$' {
			Write-JSON $MANIFEST
			break
		}

		'^/catalog/channel/(?<id>[^/.]+).json([?].*|)$' {
			$response = @{
				metas = @()
			}
			$response.metas = $CATALOG | ForEach-Object {
				@{
					id     = $_.id
					name   = $_.name
					poster = $_.poster
					genres = $_.genres
					type   = $_.type
				}
			}
			Write-JSON $response
			break
		}

		'^/catalog/channel/(?<id>[^/.]+)/skip=(?<page>[^/.]+).json([?].*|)$' {
			$response = @{
				metas = @()
			}
			Write-JSON $response
			break
		}

		'^/meta/channel/(?<id>[^/.]+).json([?].*|)$' {
			$response = @{
				meta = @{}
			}

			$meta = $CATALOG | Where-Object id -EQ $matches.id
			if ($meta) {
				$response.meta = $meta.Clone()
				$response.meta.videos = $response.meta.radios
				$response.meta.Remove('radios')
			}

			Write-JSON $response
			break
		}

		'^/stream/channel/(?<id>[^/.]+).json([?].*|)$' {
			$response = @{
				streams = @()
			}

			if ($STREAMS[$matches.id]) {
				$response.streams = $STREAMS[$matches.id]
			}

			Write-JSON $response
			break
		}

		Default {
			Write-404
		}
	}
	# powershell will continue looping and listen for new requests...
}

# Note:
# To end the loop you have to kill the powershell terminal. ctrl-c wont work :/