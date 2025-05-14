function Compress-PhoneVideo {
    <#
    .SYNOPSIS
        Compresses phone video while maintaining date/time stamp
    .DESCRIPTION
        Phones create very large files for video which uses a lot of space on the phone and on Google/Apple cloud. This script uses
        ffmpeg to compress the video but also takes the various timestamps on the files from the original video and applies them
        to the compressed video.

        This also uses ffprobe to get the video and audio codec information of the original file and applies those values to the
        conversion of the new file.
    .EXAMPLE
        Compress-PhoneVideo -VideoFolder C:\tmp\videos -ffmpegExe C:\ffmpeg\bin\ffmpeg.exe -ffprobeExe C:\ffmpeg\bin\ffprobe.exe

        Compresses all of the videos in C:\tmp\videos. The output video are automatically placed in a folder called 'Converted'
        in the 'VideoFolder' directory.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$VideoFolder,
        [Parameter(Mandatory)]
        [string]$ffmpegExe,
        [Parameter(Mandatory)]
        [string]$ffprobeExe
    )

    process {
        $currentFile = 1
        $files = Get-ChildItem -Path $VideoFolder | Where-Object {$_.extension -in ".mp4",".avi",".mkv",".mov"}
        foreach ($file in $files) {
            Write-Progress -Activity "Analyzing video $($currentFile) of $($files.Count)." -PercentComplete (($currentFile / $files.Count) * 100)
            
            # Get 'Media Created' timestamp
            $shellApplication = New-Object -ComObject Shell.Application
            $shellFolder = $shellApplication.Namespace($file.Directory.FullName)
            $shellFile = $shellFolder.ParseName($file.Name)
            $mediaCreated = $shellFile.ExtendedProperty("System.Media.DateEncoded")
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shellApplication) | Out-Null
            Remove-Variable shellApplication
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()

            if ([string]::IsNullOrEmpty($mediaCreated)) {
                Write-Warning "$($file.Name) does not have a 'Media Created' value and will be skipped."
                Continue
            }

            # Get codec info
            $streamInfo = (& $ffprobeExe -v quiet -print_format json -show_streams $file.FullName) | ConvertFrom-Json
            $videoStreamInfo = $streamInfo.streams | Where-Object codec_type -eq video
            $videoCodec = $videoStreamInfo.codec_name

            switch ($videoCodec) {
                'hevc'  {$vcodec = 'libx265'}
                'vp9'   {$vcodec = 'libvpx-vp9'}
                'h264'  {$vcodec = 'libx264'}
                default {$vcodec = 'libx265'}
            }

            # Create output directory if it doesn't exist
            if (-not (Test-Path "$($VideoFolder)\Converted")) {
                $null = New-Item -Path "$($VideoFolder)\Converted" -ItemType Directory
            }

            # Compress video using ffmpeg
            $newFileName = "$($file.BaseName)_conv$($file.Extension)"
            & $ffmpegExe -hide_banner -loglevel warning -i $file.FullName -c:v $vcodec -c:a 'aac' -b:a 256k "$($VideoFolder)\Converted\$($newFileName)"

            # Set the CreationTime and LastWriteTime timestamp to match the 'Media Created' timestamp from original file
            $machineTimeZone = Get-TimeZone
            $machineUtcOffsetMinutes = $machineTimeZone.BaseUtcOffset.TotalMinutes
            $supportsDst = $machineTimeZone.SupportsDaylightSavingTime
            $dstBeginDate = [datetime]"March 8, $($mediaCreated.Year)"
            while ($dstBeginDate.DayOfWeek -ne 'Sunday') {
                $dstBeginDate = $dstBeginDate.AddDays(1)
            }
    
            $dstEndDate = [datetime]"November 1, $($mediaCreated.Year)"
            while ($dstEndDate.DayOfWeek -ne 'Sunday') {
                $dstEndDate = $dstEndDate.AddDays(1)
            }

            if ($mediaCreated -ge $dstBeginDate -and $mediaCreated -lt $dstEndDate -and $supportsDst) {
                $dstAdjustedDate = $mediaCreated.AddMinutes($machineUtcOffsetMinutes+60)
            } else {
                $dstAdjustedDate = $mediaCreated.AddMinutes($machineUtcOffsetMinutes)
            }
                
            $newFile = Get-ChildItem -Path "$($VideoFolder)\Converted\$($newFileName)"
            $newFile.CreationTime = $dstAdjustedDate
            $newFile.LastWriteTime = $dstAdjustedDate
        
            $currentFile++
        }
        Write-Progress -Activity "Analyzing video $($currentFile) of $($files.Count)." -Completed
    }
}