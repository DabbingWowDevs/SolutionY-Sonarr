#!/bin/bash

[[ -z "$DataDir" ]] && DataDir=/opt/config
[[ -z "$QueueCheckWaitInMinutes" ]] && QueueCheckWaitInMinutes=5
QueueCheckWaitInMinutes=$(($QueueCheckWaitInMinutes * 60))
[[ $debug -eq 1 ]] && echo "[debug] Poll interval set to ${QueueCheckWaitInMinutes}s"

function MakeBlocklistFolders {
    [[ ! -d "$DataDir/BlockLists" ]] && mkdir "$DataDir/BlockLists"
    [[ ! -f "$DataDir/BlockLists/Extensions.txt" ]] && echo -e "zipx\nlnk\nexe\nbat\nsh\arj" | tee "$DataDir/BlockLists/Extensions.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/StatusMesseges.txt" ]] && echo -e "One or more episodes expected in this release were not imported or missing from the release" | tee "$DataDir/BlockLists/StatusMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/ErrorMesseges.txt" ]] && echo -e "The download is stalled with no connections" | tee "$DataDir/BlockLists/ErrorMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/Statuses.txt" ]] && echo -e "warning" | tee "$DataDir/BlockLists/Statuses.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/States.txt" ]] && echo -e "importBlocked" | tee "$DataDir/BlockLists/States.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/IgnoreClients.txt" ]] && echo -e "" | tee "$DataDir/BlockLists/IgnoreClients.txt" >/dev/null

    return
}

if [[ ! -f "$DataDir/y.config" ]]
then
    echo -e "#include port but not basedir or trailing slash\nSonarrHost=http://localhost:8989 \nSonarrApiKey=apikey \nWaitTimeMin=60 \nDataDir=$DataDir\nquiet=0\n\nremoveFromClient=true\nAddToBlocklist=true\nskipRedownload=false" | tee "$DataDir/y.config" >/dev/null
    MakeBlocklistFolders
    echo "[setup] Config files created at $DataDir — go set your API key and Sonarr host before running again."
    exit 1
fi

source $DataDir/y.config
[[ ! $quiet -eq 1 ]] && echo "[info] Verbose output enabled (quiet=0)"
[[ $debug -eq 1 ]] && echo "[debug] Debug logging enabled"

if [[ "$SonarrApiKey" == "apikey" ]]
then
    echo "[error] API key is still set to the default placeholder. Edit $DataDir/y.config and set a real API key."
    exit 1
fi
MakeBlocklistFolders

[[ ! $quiet -eq 1 ]] && echo "[info] Probing Sonarr at $SonarrHost for base path..."
BaseDirTest=$(wget "$SonarrHost/api?apikey=$SonarrApiKey" -O- 2>&1)
[[ $debug -eq 1 ]] && echo "[debug] Base path probe response: $BaseDirTest"
if echo -e "$BaseDirTest" |grep "following" >/dev/null 2>&1 || echo -e "$BaseDirTest" |grep "Location" >/dev/null 2>&1 || echo -e "$BaseDirTest" |grep "Redirect" >/dev/null 2>&1
then
        BaseDir=$(echo -e "$BaseDirTest" |grep "Location" | cut -d'/' -f2)
        [[ $debug -eq 1 ]] && echo "[debug] Detected base path: /$BaseDir"
fi

[[ ! $quiet -eq 1 ]] && echo "[info] Base path: ${BaseDir:-none (root)}"
[[ ! -z "$BaseDir" ]] && SonarrHost=$SonarrHost/$BaseDir
[[ ! $quiet -eq 1 ]] && echo "[info] Sonarr endpoint: $SonarrHost"

echo "[info] Starting queue monitor loop (check every $(($QueueCheckWaitInMinutes / 60)) min, act on items older than ${WaitTimeMin} min)"
while true
do
    [[ ! $quiet -eq 1 ]] && echo ""
    [[ ! $quiet -eq 1 ]] && echo "[poll] Fetching Sonarr queue..."
[[ $debug -eq 1 ]] && echo "[debug] Request URL: $SonarrHost/api/v3/queue?page=1&pageSize=200&includeUnknownSeriesItems=false&includeSeries=false&includeEpisode=false&protocol=torrent&apikey=***"

QueueJsonRaw=$(curl -s "\
$SonarrHost/api/v3/queue?page=1\
&pageSize=200\
&includeUnknownSeriesItems=false\
&includeSeries=false\
&includeEpisode=false\
&protocol=torrent\
&apikey=$SonarrApiKey\
" 2>&1)

    [[ $debug -eq 1 ]] && echo "[debug] Raw response:"$'\n'"$QueueJsonRaw"$'\n'
    if [[ -z "$QueueJsonRaw" ]]; then
        echo "[error] Got empty response from Sonarr — is it running and reachable?"
        exit 1
    fi
    echo -e "$QueueJsonRaw" | jq '.' >/dev/null 2>&1 || { echo "[error] Sonarr returned non-JSON — check host/API key config."; exit 1; }
    QueueItemCount=$(echo -e "$QueueJsonRaw" | jq '.[\"totalRecords\"]')
    [[ ! $quiet -eq 1 ]] && echo "[poll] $QueueItemCount item(s) in queue"
    [[ $debug -eq 1 ]] && echo "[debug] Total records: $QueueItemCount"

    function BlacklistQueueItem {
        [[ ! $quiet -eq 1 ]] && echo "[action] Blocklisting: $1 (id=$2) — removeFromClient=$removeFromClient, blocklist=$AddToBlocklist, skipRedownload=$skipRedownload"
        curl -X 'DELETE' "$SonarrHost/api/v3/queue/$2?removeFromClient=$removeFromClient&blocklist=$AddToBlocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=$SonarrApiKey" -H 'accept: */*'
        sleep 1
        return
    }

    for QueueItemIndex in  $(seq 0 $((${QueueItemCount}-1)))
    do
        blacklist=0

        title=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].title')

        id=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].id')

        episodeId=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].episodeId')
        seriesId=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].seriesId')
        downloadClient=$(echo -e "$QueueJsonRaw" | jq -r '.[\"records\"]['$QueueItemIndex'].downloadClient')
        #seasonNumber=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].seasonNumber')

        status=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].status')
        trackedDownloadState=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].trackedDownloadState')
        errorMessage=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].errorMessage')

        StatusMessegesRaw=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].statusMessages[]')

        added=$(echo -e "$QueueJsonRaw" | jq '.[\"records\"]['$QueueItemIndex'].added'|sed 's|\"||g')

        AddedEpoch=$(date -d"$added" +%s)
        NowEpoch=$(date +%s)
        SecSinceAdded=$(($NowEpoch - $AddedEpoch))
        MinSinceAdded=$(($SecSinceAdded / 60))

        if [[ ! $quiet -eq 1 ]]; then
            echo ""
            echo "  ┌─ [$((QueueItemIndex+1))/$QueueItemCount] $title"
            echo "  │  id=$id  series=$seriesId  ep=$episodeId"
            echo "  │  client=$downloadClient"
            echo "  │  state=$trackedDownloadState  status=$status"
            echo "  │  error=$errorMessage"
            echo "  │  age=${MinSinceAdded}min (added $added)"
            if [[ ! -z "$StatusMessegesRaw" ]]; then
                echo "  │  status messages:"
                StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.[\"title\"]';echo $StatusMessegesRaw | jq '.messages[]')
                while IFS= read -r line || [[ -n $line ]]; do
                    echo "  │    $line"
                done < <(printf '%s' "$StatusMessegesLines")
            fi
        fi

        # Skip items assigned to an ignored download client
        ignoreClient=0
        while IFS= read -r IgnoreFilter || [[ -n $IgnoreFilter ]]; do
            [[ -z "$IgnoreFilter" ]] && continue
            if echo -e "$downloadClient" | grep -qi "$IgnoreFilter"; then
                [[ ! $quiet -eq 1 ]] && echo "  └─ [skip] Client '$downloadClient' is in IgnoreClients.txt — skipping"
                ignoreClient=1
                break
            fi
        done <"$DataDir/BlockLists/IgnoreClients.txt"
        [[ $ignoreClient -eq 1 ]] && continue

        if [[ ! -z "$StatusMessegesRaw" ]] && [[ $quiet -eq 1 ]]
        then
            StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.[\"title\"]';echo $StatusMessegesRaw | jq '.messages[]' )
        fi
        [[ $MinSinceAdded -gt $WaitTimeMin ]] && process=1 || process=0

        if [[ $process -eq 0 ]]; then
            [[ ! $quiet -eq 1 ]] && echo "  └─ [skip] Only ${MinSinceAdded}min old — below ${WaitTimeMin}min threshold"
            continue
        fi

        [[ ! $quiet -eq 1 ]] && echo "  │  [check] Item is ${MinSinceAdded}min old — checking filters..."

        found=0

        while IFS= read -r Filter || [[ -n $Filter ]]; do
            if [[ ! -z "$StatusMessegesRaw" ]]
            then
                StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.[\"title\"]';echo $StatusMessegesRaw | jq '.messages[]' )
                while IFS= read -r line || [[ -n $line ]]; do
                    #"Invalid video file, unsupported extension: '.ext'"
                    check=$(echo -e "   $line" | grep -i -e "unsupported" -e "extension\:"| grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                    if [[ $check -eq 1 ]]
                    then
                        [[ ! $quiet -eq 1 ]] && echo "  │  [match] Blocked extension '$Filter' found in status messages"
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
                        [[ ! $quiet -eq 1 ]] && echo "  │  [match] Blocked extension '$Filter' found in 'no eligible files' message"
                        found=1
                        blacklist=1
                        continue
                    fi
                done < <(printf '%s' "$StatusMessegesLines")
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/Extensions.txt"


        while IFS= read -r Filter || [[ -n $Filter ]]; do
            if [[ ! -z "$StatusMessegesRaw" ]]
            then
                StatusMessegesLines=$(echo $StatusMessegesRaw | jq '.[\"title\"]';echo $StatusMessegesRaw | jq '.messages[]' )
                while IFS= read -r line || [[ -n $line ]]; do
                    check=$(echo -e "   $line" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                    if [[ $check -eq 1 ]]
                    then
                        [[ ! $quiet -eq 1 ]] && echo "  │  [match] Status message filter matched: '$Filter'"
                        found=1
                        blacklist=1
                        continue
                    fi
                done < <(printf '%s' "$StatusMessegesLines")
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/StatusMesseges.txt"


        while IFS= read -r Filter || [[ -n $Filter ]]; do
            if [[ ! -z "$errorMessage" ]]
            then
                check=$(echo -e "   $errorMessage" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                if [[ $check -eq 1 ]]
                then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] Error message filter matched: '$Filter'"
                    found=1
                    blacklist=1
                fi
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/ErrorMesseges.txt"


        while IFS= read -r Filter || [[ -n $Filter ]]; do
            if [[ ! -z "$status" ]]
            then
                check=$(echo -e "   $status" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                if [[ $check -eq 1 ]]
                then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] Status filter matched: '$Filter'"
                    found=1
                    blacklist=1
                fi
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/Statuses.txt"


        while IFS= read -r Filter || [[ -n $Filter ]]; do
            if [[ ! -z "$status" ]]
            then
                check=$(echo -e "   $trackedDownloadState" | grep -i "$Filter" >/dev/null 2>&1 && echo 1 || echo 0)
                if [[ $check -eq 1 ]]
                then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] State filter matched: '$Filter'"
                    found=1
                    blacklist=1
                fi
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/States.txt"

        if [[ $blacklist -eq 1 ]]; then
            [[ ! $quiet -eq 1 ]] && echo "  └─ [action] Blocklisting item (id=$id)"
            BlacklistQueueItem "$title" "$id"
        else
            [[ ! $quiet -eq 1 ]] && echo "  └─ [ok] No filters matched — leaving alone"
        fi
    done
    [[ ! $quiet -eq 1 ]] && echo ""
    [[ ! $quiet -eq 1 ]] && echo "[poll] Done. Sleeping for $(($QueueCheckWaitInMinutes / 60)) minute(s)..."
    sleep $QueueCheckWaitInMinutes
done
