#!/bin/bash
CorpID='***Your CorpID***'
Secret='***Your Secret***'
AppID='***Your AppID***'
Content=$2"\n"$(echo "$@" | cut -d" " -f3-)

GURL="https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=$CorpID&corpsecret=$Secret"
Gtoken=$(/usr/bin/curl -s -G "$GURL" | awk -F\" '{print $10}')

PURL="https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=$Gtoken"
/usr/bin/curl -s --data-ascii '{ "touser": "'$1'", "msgtype": "text", "agentid": "'$AppID'","text": {"content": "'"${Content//\"/\\\"}"'"},"safe":"0"}' "$PURL"
