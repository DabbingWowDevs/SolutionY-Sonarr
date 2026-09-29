#!/bin/bash

[[ -z "$DataDir" ]] && DataDir=/opt/config
[[ -z "$QueueCheckWaitInMinutes" ]] && QueueCheckWaitInMinutes=5
QueueCheckWaitInMinutes=$(($QueueCheckWaitInMinutes * 60))
[[ $debug -eq 1 ]] && echo "[debug] Poll interval set to ${QueueCheckWaitInMinutes}s"

function MakeBlocklistFolders {
    [[ ! -d "$DataDir/BlockLists" ]] && mkdir "$DataDir/BlockLists"
    [[ ! -f "$DataDir/BlockLists/Extensions.txt" ]] && echo -e "zipx\nlnk\nexe\nbat\nsh\narj" | tee "$DataDir/BlockLists/Extensions.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/StatusMesseges.txt" ]] && echo -e "One or more episodes expected in this release were not imported or missing from the release" | tee "$DataDir/BlockLists/StatusMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/ErrorMesseges.txt" ]] && echo -e "The download is stalled with no connections" | tee "$DataDir/BlockLists/ErrorMesseges.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/Statuses.txt" ]] && echo -e "warning" | tee "$DataDir/BlockLists/Statuses.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/States.txt" ]] && echo -e "importBlocked" | tee "$DataDir/BlockLists/States.txt" >/dev/null
    [[ ! -f "$DataDir/BlockLists/IgnoreClients.txt" ]] && echo -e "" | tee "$DataDir/BlockLists/IgnoreClients.txt" >/dev/null
    return
}

if [[ ! -f "$DataDir/y.config" ]]; then
    echo -e "#include port but not basedir or trailing slash\nSonarrHost=http://localhost:8989 \nSonarrApiKey=apikey \nWaitTimeMin=60 \nDataDir=$DataDir\nquiet=0\n\nremoveFromClient=true\nAddToBlocklist=true\nskipRedownload=false" | tee "$DataDir/y.config" >/dev/null
    MakeBlocklistFolders
    echo "[setup] Config files created at $DataDir — go set your API key and Sonarr host before running again."
    exit 1
fi

source $DataDir/y.config
[[ ! $quiet -eq 1 ]] && echo "[info] Verbose output enabled (quiet=0)"
[[ $debug -eq 1 ]] && echo "[debug] Debug logging enabled"

if [[ "$SonarrApiKey" == "apikey" ]]; then
    echo "[error] API key is still set to the default placeholder. Edit $DataDir/y.config and set a real API key."
    exit 1
fi
MakeBlocklistFolders

[[ ! $quiet -eq 1 ]] && echo "[info] Probing Sonarr at $SonarrHost for base path..."
BaseDirTest=$(wget "$SonarrHost/api?apikey=$SonarrApiKey" -O- 2>&1)
[[ $debug -eq 1 ]] && echo "[debug] Base path probe response: $BaseDirTest"
if echo "$BaseDirTest" | grep -q "following\|Location\|Redirect"; then
    BaseDir=$(echo "$BaseDirTest" | grep "Location" | cut -d'/' -f2)
    [[ $debug -eq 1 ]] && echo "[debug] Detected base path: /$BaseDir"
fi

[[ ! $quiet -eq 1 ]] && echo "[info] Base path: ${BaseDir:-none (root)}"
[[ ! -z "$BaseDir" ]] && SonarrHost=$SonarrHost/$BaseDir
[[ ! $quiet -eq 1 ]] && echo "[info] Sonarr endpoint: $SonarrHost"

echo "[info] Starting queue monitor loop (check every $(($QueueCheckWaitInMinutes / 60)) min, act on items older than ${WaitTimeMin} min)"

while true; do
    [[ ! $quiet -eq 1 ]] && echo ""
    [[ ! $quiet -eq 1 ]] && echo "[poll] Fetching Sonarr queue..."
    [[ $debug -eq 1 ]] && echo "[debug] Request URL: $SonarrHost/api/v3/queue?page=1&pageSize=200&...&apikey=***"

    QueueJsonRaw=$(curl -s "$SonarrHost/api/v3/queue?page=1&pageSize=200&includeUnknownSeriesItems=false&includeSeries=false&includeEpisode=false&protocol=torrent&apikey=$SonarrApiKey" 2>&1)

    [[ $debug -eq 1 ]] && echo "[debug] Raw response:" && echo "$QueueJsonRaw" && echo ""

    if [[ -z "$QueueJsonRaw" ]]; then
        echo "[error] Got empty response from Sonarr — is it running and reachable?"
        exit 1
    fi
    echo "$QueueJsonRaw" | jq '.' >/dev/null 2>&1 || { echo "[error] Sonarr returned non-JSON — check host/API key config."; exit 1; }

    QueueItemCount=$(echo "$QueueJsonRaw" | jq '.totalRecords')
    [[ ! $quiet -eq 1 ]] && echo "[poll] $QueueItemCount item(s) in queue"
    [[ $debug -eq 1 ]] && echo "[debug] Total records: $QueueItemCount"

    function BlacklistQueueItem {
        [[ ! $quiet -eq 1 ]] && echo "[action] Blocklisting: $1 (id=$2) — removeFromClient=$removeFromClient, blocklist=$AddToBlocklist, skipRedownload=$skipRedownload"
        curl -X 'DELETE' "$SonarrHost/api/v3/queue/$2?removeFromClient=$removeFromClient&blocklist=$AddToBlocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=$SonarrApiKey" -H 'accept: */*'
        sleep 1
        return
    }

    for QueueItemIndex in $(seq 0 $((${QueueItemCount}-1))); do
        blacklist=0

        title=$(echo "$QueueJsonRaw"            | jq -r ".records[$QueueItemIndex].title")
        id=$(echo "$QueueJsonRaw"               | jq -r ".records[$QueueItemIndex].id")
        episodeId=$(echo "$QueueJsonRaw"        | jq -r ".records[$QueueItemIndex].episodeId")
        seriesId=$(echo "$QueueJsonRaw"         | jq -r ".records[$QueueItemIndex].seriesId")
        downloadClient=$(echo "$QueueJsonRaw"   | jq -r ".records[$QueueItemIndex].downloadClient")
        status=$(echo "$QueueJsonRaw"           | jq -r ".records[$QueueItemIndex].status")
        trackedDownloadState=$(echo "$QueueJsonRaw" | jq -r ".records[$QueueItemIndex].trackedDownloadState")
        errorMessage=$(echo "$QueueJsonRaw"     | jq -r ".records[$QueueItemIndex].errorMessage")
        added=$(echo "$QueueJsonRaw"            | jq -r ".records[$QueueItemIndex].added")
        StatusMessegesRaw=$(echo "$QueueJsonRaw" | jq -c ".records[$QueueItemIndex].statusMessages[]?" 2>/dev/null)

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
                while IFS= read -r msgobj; do
                    msgtitle=$(echo "$msgobj" | jq -r '.title')
                    echo "  │    $msgtitle"
                    echo "$msgobj" | jq -r '.messages[]?' | while IFS= read -r m; do
                        echo "  │      $m"
                    done
                done < <(printf '%s\n' "$StatusMessegesRaw")
            fi
        fi

        # Skip items assigned to an ignored download client
        ignoreClient=0
        while IFS= read -r IgnoreFilter || [[ -n $IgnoreFilter ]]; do
            [[ -z "$IgnoreFilter" ]] && continue
            if echo "$downloadClient" | grep -qi "$IgnoreFilter"; then
                [[ ! $quiet -eq 1 ]] && echo "  └─ [skip] Client '$downloadClient' is in IgnoreClients.txt — skipping"
                ignoreClient=1
                break
            fi
        done <"$DataDir/BlockLists/IgnoreClients.txt"
        [[ $ignoreClient -eq 1 ]] && continue

        if [[ $MinSinceAdded -le $WaitTimeMin ]]; then
            [[ ! $quiet -eq 1 ]] && echo "  └─ [skip] Only ${MinSinceAdded}min old — below ${WaitTimeMin}min threshold"
            continue
        fi

        [[ ! $quiet -eq 1 ]] && echo "  │  [check] Item is ${MinSinceAdded}min old — checking filters..."

        found=0

        # Extensions filter
        while IFS= read -r Filter || [[ -n $Filter ]]; do
            [[ -z "$Filter" ]] && continue
            if [[ ! -z "$StatusMessegesRaw" ]]; then
                while IFS= read -r msgobj; do
                    StatusMessegesLines=$(echo "$msgobj" | jq -r '.title, (.messages[]? // empty)')
                    while IFS= read -r line || [[ -n $line ]]; do
                        if echo "$line" | grep -qi -e "unsupported" -e "extension:" && echo "$line" | grep -qi "$Filter"; then
                            [[ ! $quiet -eq 1 ]] && echo "  │  [match] Blocked extension '$Filter' found in status messages"
                            found=1; blacklist=1
                        fi
                        if echo "$line" | grep -qi "No files found are eligible for import" && echo "$line" | grep -qi "$Filter"; then
                            [[ ! $quiet -eq 1 ]] && echo "  │  [match] Blocked extension '$Filter' found in 'no eligible files' message"
                            found=1; blacklist=1
                        fi
                    done < <(printf '%s\n' "$StatusMessegesLines")
                done < <(printf '%s\n' "$StatusMessegesRaw")
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/Extensions.txt"

        # StatusMessages filter
        while IFS= read -r Filter || [[ -n $Filter ]]; do
            [[ -z "$Filter" ]] && continue
            if [[ ! -z "$StatusMessegesRaw" ]]; then
                while IFS= read -r msgobj; do
                    StatusMessegesLines=$(echo "$msgobj" | jq -r '.title, (.messages[]? // empty)')
                    while IFS= read -r line || [[ -n $line ]]; do
                        if echo "$line" | grep -qi "$Filter"; then
                            [[ ! $quiet -eq 1 ]] && echo "  │  [match] Status message filter matched: '$Filter'"
                            found=1; blacklist=1
                        fi
                    done < <(printf '%s\n' "$StatusMessegesLines")
                done < <(printf '%s\n' "$StatusMessegesRaw")
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/StatusMesseges.txt"

        # ErrorMessages filter
        while IFS= read -r Filter || [[ -n $Filter ]]; do
            [[ -z "$Filter" ]] && continue
            if [[ ! -z "$errorMessage" ]]; then
                if echo "$errorMessage" | grep -qi "$Filter"; then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] Error message filter matched: '$Filter'"
                    found=1; blacklist=1
                fi
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/ErrorMesseges.txt"

        # Statuses filter
        while IFS= read -r Filter || [[ -n $Filter ]]; do
            [[ -z "$Filter" ]] && continue
            if [[ ! -z "$status" ]]; then
                if echo "$status" | grep -qi "$Filter"; then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] Status filter matched: '$Filter'"
                    found=1; blacklist=1
                fi
            fi
            [[ $found -eq 1 ]] && continue
        done <"$DataDir/BlockLists/Statuses.txt"

        # States filter
        while IFS= read -r Filter || [[ -n $Filter ]]; do
            [[ -z "$Filter" ]] && continue
            if [[ ! -z "$trackedDownloadState" ]]; then
                if echo "$trackedDownloadState" | grep -qi "$Filter"; then
                    [[ ! $quiet -eq 1 ]] && echo "  │  [match] State filter matched: '$Filter'"
                    found=1; blacklist=1
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
