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
        #指定access_token缓存文件路径
        self.TokenFile = '/tmp/.wechat_access_token'

    def _get_access_token(self):
        _url = 'https://qyapi.weixin.qq.com/cgi-bin/gettoken'
        _values = {'corpid': self.CORPID,
                  'corpsecret': self.SECRET,
                  }
        _req = requests.post(_url, params=_values)
        data = json.loads(_req.text)
        if data['errcode'] != 0:
            print(_req.text)
        else:
            return data["access_token"]

    def get_access_token(self):
        try:
            with open(self.TokenFile, 'r') as f:
                tt, access_token = f.read().split()
        except:
            with open(self.TokenFile, 'w') as f:
                access_token = self._get_access_token()
                curr_time = time.time()
                f.write('\t'.join([str(curr_time), access_token]))
                return access_token
        else:
            curr_time = time.time()
            if 0 < curr_time - float(tt) < 7260:
                return access_token
            else:
                with open(self.TokenFile, 'w') as f:
                    access_token = self._get_access_token()
                    f.write('\t'.join([str(curr_time), access_token]))
                    return access_token

    def renew_access_token(self):
        with open(self.TokenFile, 'w') as f:
            access_token = self._get_access_token()
            curr_time = time.time()
            f.write('\t'.join([str(curr_time), access_token]))
            return access_token

    def send_data(self, User, Subject, Message):
        try:
            access_token = self.get_access_token()
        except:
            sys.exit("获取access_token失败！")
        else:
            _url = 'https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=' + access_token
            _data = {
                "touser": User,
                "msgtype": "text",
                "agentid": self.AGENTID,
                "text": {
                    "content": Subject + '\n' + Message
                    },
                "safe": "0"
                }
            _values = bytes(json.dumps(_data), 'utf-8')
            _req = requests.post(_url, _values)
            return(json.loads(_req.text))

if __name__ == '__main__':
    User = sys.argv[1]
    Subject = str(sys.argv[2])
    Message = str(sys.argv[3])
    wx = WeChat()
    log = wx.send_data(User, Subject, Message)
    #如果access_token过期或错误，重试一次
    if log['errcode'] == 42001 or log['errcode'] == 40014:
        wx.renew_access_token()
        log = wx.send_data(User, Subject, Message)
    if log['errcode'] == 0:
        print(log['errmsg'])
    else:
        print(log)
