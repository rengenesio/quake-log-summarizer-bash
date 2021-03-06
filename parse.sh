#!/bin/bash

tempDir=`mktemp -d`
csplit -sz -f $tempDir/ $1 "/InitGame: /" '{*}'

tempDir=$tempDir/*

index=1
for matchLog in $tempDir; do
    # Avoid processing first file without any Quake match (generated by csplit)
    if ! grep -q "InitGame: " "$matchLog"; then
        continue
    fi

    players=`grep " ClientUserinfoChanged: " $matchLog \
        | sed 's|.*ClientUserinfoChanged: \([0-9]\+\) n\\\\\([^\\]*\\).*|\1;\2|' \
        | sort -t ';' -u -k1,1`

    kills=`grep " Kill: " $matchLog \
        | wc -l`

    playerKilled=`grep " Kill: " $matchLog \
        | grep -v " Kill: 1022" \
        | grep -vE " Kill: ([0-9]+) \1" \
        | sed 's|.*Kill: \([0-9]\+\) \([0-9]\+\).*|\1|' \
        | sort \
        | uniq -c \
        | awk '{print $2";"$1}'`

    worldKilled=`grep " Kill: 1022" $matchLog \
        | sed 's|.*Kill: 1022 \([0-9]\+\).*|\1|' \
        | sort \
        | uniq -c \
        | awk '{print $2";"$1}'`

    leftJoin=`join -t';' <(echo "$playerKilled") <(echo "$worldKilled") -a1`
    rightJoin=`join -t';' <(echo "$playerKilled") <(echo "$worldKilled") -a2`
    fullOuterJoin=`sort <<< "$leftJoin"$'\n'"$rightJoin" \
        | uniq`

    final=`join -t';' <(echo "$players") <(echo "$fullOuterJoin") -a1`

    score=`awk -F ';' '{ score=0; score+=$3; score-=$4; print $2";"score }' <<< "$final"`

    jq -n --arg index $index --arg totalKills "$kills" --arg players "$players" --arg score "$score" '
        ([$players | split("\n") | .[] | split(";") | .[1]]) as $playersJson
        | (([$score | split("\n") | .[] | split(";") | .[0]]) as $keys | ([$score | split("\n") | .[] | split(";") | .[1]]) as $values | [[$keys, $values] | transpose[] | {key:.[0],value:.[1]}] | from_entries) as $score
        | { "game_\($index)": { players: $playersJson, total_kills: $totalKills, kills: $score } }'

    ((index++))
done
