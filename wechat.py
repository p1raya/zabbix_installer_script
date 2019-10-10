#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import json
import time
import sys

class WeChat:
    def __init__(self):
        #在此填入企业ID
        self.CORPID = '***Your CorpID***'
        #在此填入消息应用的凭证密钥
        self.SECRET = '***Your Secret***'
        #在此填入消息应用的agentid
        self.AGENTID = '1'

    def _get_access_token(self):
        _url = 'https://qyapi.weixin.qq.com/cgi-bin/gettoken'
        _values = {'corpid': self.CORPID,
                  'corpsecret': self.SECRET,
                  }
        _req = requests.post(_url, params=_values)
        data = _req.json()
        if data['errcode'] != 0:
            print(_req.text)
        else:
            return data["access_token"]

    def get_access_token(self):
        try:
            with open('/tmp/.wechat_access_token', 'r') as f:
                tt, access_token = f.read().split()
        except:
            with open('/tmp/.wechat_access_token', 'w') as f:
                access_token = self._get_access_token()
                curr_time = time.time()
                f.write('\t'.join([str(curr_time), access_token]))
                return access_token
        else:
            curr_time = time.time()
            if (0 < curr_time - float(tt) < 7260):
                return access_token
            else:
                with open('/tmp/.wechat_access_token', 'w') as f:
                    access_token = self._get_access_token()
                    f.write('\t'.join([str(curr_time), access_token]))
                    return access_token

    def send_data(self, User, Subject, Message):
        try:
            _token = self.get_access_token()
        except:
            sys.exit("获取 access_token 失败！")
        else:
            _url = 'https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=' + _token
            _data = {
                "touser": User,
                "msgtype": "text",
                "agentid": self.AGENTID,
                "text": {
                    "content": Subject + '\n' + Message
                    },
                "safe": "0"
                }
            _values=(bytes(json.dumps(_data), 'utf-8'))
            _req = requests.post(_url, _values)
            respone = _req.json()
            return respone["errmsg"]

if __name__ == '__main__':
    User = sys.argv[1]
    Subject = str(sys.argv[2])
    Message = str(sys.argv[3])
    wx = WeChat()
    log = wx.send_data(User, Subject, Message)
    print(log)
