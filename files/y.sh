#!/bin/bash

[[ -z "$DataDir" ]] && DataDir=/opt/config
[[ -z "$QueueCheckWaitInMinutes" ]] && QueueCheckWaitInMinutes=5
QueueCheckWaitInMinutes=$(($QueueCheckWaitInMinutes * 60))
[[ $debug -eq 1 ]] && echo QueueCheckWaitInMinutes=$QueueCheckWaitInMinutes
function MakeBlocklistFolders {
    [[ ! -d "$DataDir/BlockLists" ]] && mkdir "$DataDir/BlockLists"
    [[ ! -f "$DataDir/BlockLists/Extensions.txt" ]] && echo -e "zipx\nlnk\nexe\nbat\nsh\arj" | tee "$DataDir/BlockLists/Extensions.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/StatusMesseges.txt" ]] && echo -e "One or more episodes expected in this release were not imported or missing from the release" | tee "$DataDir/BlockLists/StatusMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/ErrorMesseges.txt" ]] && echo -e "The download is stalled with no connections" | tee "$DataDir/BlockLists/ErrorMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/Statuses.txt" ]] && echo -e "warning" | tee "$DataDir/BlockLists/Statuses.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/States.txt" ]] && echo -e "importBlocked" | tee "$DataDir/BlockLists/States.txt" >/dev/null

    return
}

if [[ ! -f "$DataDir/y.config" ]]
then    
    echo -e "#include port but not basedir or trailing slash\nSonarrHost=http://localhost:8989 \nSonarrApiKey=apikey \nWaitTimeMin=60 \nDataDir=$DataDir\nquiet=0\n\nremoveFromClient=true\nAddToBlocklist=true\nskipRedownload=false" | tee "$DataDir/y.config" >/dev/null
    MakeBlocklistFolders
    echo Config files created, you should go change them now.
    exit 1
fi

source $DataDir/y.config
[[ ! $quiet -eq 1 ]] && echo not quiet
[[ $debug -eq 1 ]] && echo -e "Debug On"
if [[ "$SonarrApiKey" == "apikey" ]]
then    
    echo -e "Config files created, you should go change them now. (no apikey)"
    exit 1
fi
MakeBlocklistFolders

BaseDirTest=$(wget "$SonarrHost/api?apikey=$SonarrApiKey" -O- 2>&1)
[[ $debug -eq 1 ]] && echo BaseDirTest=$BaseDirTest
if echo -e "$BaseDirTest" |grep "following" >/dev/null 2>&1 || echo -e "$BaseDirTest" |grep "Location" >/dev/null 2>&1 || echo -e "$BaseDirTest" |grep "Redirect" >/dev/null 2>&1
then
        BaseDir=$(echo -e "$BaseDirTest" |grep "Location" | cut -d'/' -f2)
        [[ $debug -eq 1 ]] && echo BaseDir=$BaseDir
fi

echo basedir is $BaseDir
[[ ! -z "$BaseDir" ]] && SonarrHost=$SonarrHost/$BaseDir
echo SonarrHost is $SonarrHost

echo loop start
while true 
do
    echo looping...
[[ $debug -eq 1 ]] && echo -e "\
$SonarrHost/api/v3/queue?page=1\
&pageSize=10\
&includeUnknownSeriesItems=false\
&includeSeries=false\
&includeEpisode=false\
&protocol=torrent\
&apikey=$SonarrApiKey\
"

QueueJsonRaw=$(curl -s "\
$SonarrHost/api/v3/queue?page=1\
&pageSize=10\
&includeUnknownSeriesItems=false\
&includeSeries=false\
&includeEpisode=false\
&protocol=torrent\
&apikey=$SonarrApiKey\
" 2>&1)
    
    [[ $debug -eq 1 ]] && echo -e "Raw Json: \n\n$QueueJsonRaw\n\n"
    [[ -z "$QueueJsonRaw" ]] && exit 1
    echo -e "$QueueJsonRaw" | jq '.' >/dev/null 2>&1 || exit 1
    QueueItemCount=$(echo -e "$QueueJsonRaw" | jq '.["totalRecords"]')
    [[ $debug -eq 1 ]] && echo -e "QueueItemCount: \n\n$QueueItemCount\n\n"
    
    function BlacklistQueueItem {
        
        curl -X 'DELETE' "$SonarrHost/api/v3/queue/$2?removeFromClient=$removeFromClient&blocklist=$AddToBlocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=$SonarrApiKey" -H 'accept: */*'
        sleep 1
        return
    }
    
    for QueueItemIndex in  $(seq 0 $((${QueueItemCount}-1)))
    do
        blacklist=0
        
        title=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].title')
    
        id=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].id')
    
        episodeId=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].episodeId')
        seriesId=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].seriesId')
        #seasonNumber=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].seasonNumber')
    
        status=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].status')
        trackedDownloadState=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].trackedDownloadState')
        errorMessage=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].errorMessage')
    
        StatusMessegesRaw=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].statusMessages[]')
    
        added=$(echo -e "$QueueJsonRaw" | jq '.["records"]['$QueueItemIndex'].added'|sed 's|\"||g')
    
        AddedEpoch=$(date -d"$added" +%s)
        NowEpoch=$(date +%s)
        SecSinceAdded=$(($NowEpoch - $AddedEpoch))
        MinSinceAdded=$(($SecSinceAdded / 60))
        [[ ! $quiet -eq 1 ]] && echo
        [[ ! $quiet -eq 1 ]] && echo -e "Title: $title\n  ID: $id\n  SeriesID: $seriesId\n  EpID: $episodeId\n  State: $trackedDownloadState\n  Status: $status\n  ErrorMessage: $errorMessage\n  StatusMesseges:"
        if [[ ! -z "$StatusMessegesRaw" ]] 
        then
            StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.["title"]';echo $StatusMessegesRaw | jq '.messages[]' )
            while IFS= read -r line || [[ -n $line ]]; do
                [[ ! $quiet -eq 1 ]] && echo -e "   $line"
            done < <(printf '%s' "$StatusMessegesLines")
        fi
        [[ ! $quiet -eq 1 ]] && echo -e "  Added On: $added\n  Added On (epoch): $AddedEpoch\n  Seconds Since Added: $SecSinceAdded\n  Minutes Since Added: $MinSinceAdded"
        [[ $MinSinceAdded -gt $WaitTimeMin ]] && process=1 || process=0 
    
        if [[ $process -eq 1 ]] 
        then
            [[ ! $quiet -eq 1 ]] && echo -e "  Would process"
    
            found=0
    
            while IFS= read -r Filter || [[ -n $Filter ]]; do
                #echo "    check extension $Filter"
                if [[ ! -z "$StatusMessegesRaw" ]] 
                then
                    StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.["title"]';echo $StatusMessegesRaw | jq '.messages[]' )
                    while IFS= read -r line || [[ -n $line ]]; do
                        #"Invalid video file, unsupported extension: '.ext'"
                        check=$(echo -e "   $line" | grep -i -e "unsupported" -e "extension\:"| grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                        if [[ $check -eq 1 ]] 
                        then
                            [[ ! $quiet -eq 1 ]] && echo -e "    found extension $Filter, would blacklist."
                            found=1
                            blacklist=1
                            continue
                        fi
                    done < <(printf '%s' "$StatusMessegesLines")
                    
                    while IFS= read -r line || [[ -n $line ]]; do
                        #"No files found are eligible for import '.ext'"
                        check=$(echo -e "   $line" | grep -i -e "No files found are eligible for import"| grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                        if [[ $check -eq 1 ]] 
                        then
                            [[ ! $quiet -eq 1 ]] && echo -e "    found extension $Filter, would blacklist."
                            found=1
                            blacklist=1
                            continue
                        fi
                    done < <(printf '%s' "$StatusMessegesLines")
                fi
                [[ $found -eq 1 ]] && continue
            done <"$DataDir/BlockLists/Extensions.txt"
            #[[ $found -eq 1 ]] && continue
    
    
            while IFS= read -r Filter || [[ -n $Filter ]]; do
                #echo "    check StatusMesseges $Filter"
                if [[ ! -z "$StatusMessegesRaw" ]] 
                then
                    StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.["title"]';echo $StatusMessegesRaw | jq '.messages[]' )
                    while IFS= read -r line || [[ -n $line ]]; do
                        check=$(echo -e "   $line" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                        if [[ $check -eq 1 ]] 
                        then
                            [[ ! $quiet -eq 1 ]] && echo -e "    found StatusMessege Filter, would blacklist. ($Filter)"
                            found=1
                            blacklist=1
                            continue
                        fi
                    done < <(printf '%s' "$StatusMessegesLines")
                fi
                [[ $found -eq 1 ]] && continue
            done <"$DataDir/BlockLists/StatusMesseges.txt"
            #[[ $found -eq 1 ]] && continue
    
    
            while IFS= read -r Filter || [[ -n $Filter ]]; do
                #echo "    check ErrorMesseges $Filter"
                if [[ ! -z "$errorMessage" ]] 
                then
                    check=$(echo -e "   $errorMessage" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                    if [[ $check -eq 1 ]] 
                    then
                        [[ ! $quiet -eq 1 ]] && echo -e "    found ErrorMessege Filter, would blacklist. ($Filter)"
                        found=1
                        blacklist=1
                    fi
                fi
                [[ $found -eq 1 ]] && continue
            done <"$DataDir/BlockLists/ErrorMesseges.txt"
            #[[ $found -eq 1 ]] && continue
    
    
            while IFS= read -r Filter || [[ -n $Filter ]]; do
                #echo "    check Statuses $Filter"
                if [[ ! -z "$status" ]] 
                then
                    check=$(echo -e "   $status" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                    if [[ $check -eq 1 ]] 
                    then
                        [[ ! $quiet -eq 1 ]] && echo -e "    found status Filter, would blacklist. ($Filter)"
                        found=1
                        blacklist=1
                    fi
                fi
                [[ $found -eq 1 ]] && continue
            done <"$DataDir/BlockLists/Statuses.txt"
    
    
            while IFS= read -r Filter || [[ -n $Filter ]]; do
                #echo "    check Statuses $Filter"
                if [[ ! -z "$status" ]] 
                then
                    check=$(echo -e "   $trackedDownloadState" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                    if [[ $check -eq 1 ]] 
                    then
                        [[ ! $quiet -eq 1 ]] && echo -e "    found state Filter, would blacklist. ($Filter)"
                        found=1
                        blacklist=1
                    fi
                fi
                [[ $found -eq 1 ]] && continue
            done <"$DataDir/BlockLists/States.txt"
    
        fi
    
        [[ $blacklist -eq 1 ]] &&  BlacklistQueueItem "$title" "$id" 
        [[ ! $quiet -eq 1 ]] && echo  end 
    done
    sleep $QueueCheckWaitInMinutes
done
