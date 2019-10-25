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
        self.TOKENFILE = '/tmp/.wechat_access_token'

    def get_access_token(self):
        url = 'https://qyapi.weixin.qq.com/cgi-bin/gettoken'
        values = {'corpid': self.CORPID, 'corpsecret': self.SECRET}
        req = requests.post(url, params=values)
        if req.status_code == 200:
            data = json.loads(req.text)
            if data['errcode'] == 0:
                try:
                    with open(self.TOKENFILE, 'w') as f:
                        f.write('\t'.join([str(time.time()), data["access_token"]]))
                except:
                    print("文件" + self.TOKENFILE + "写入出错！")
                return data["access_token"]
        sys.exit("请求access_token失败！")

    def read_access_token(self):
        try:
            with open(self.TOKENFILE, 'r') as f:
                tt, access_token = f.read().split()
        except:
            return(self.get_access_token())
        else:
            if 0 < (time.time() - float(tt)) < 7260:
                return access_token
            else:
                return(self.get_access_token())

    def send_message(self, User, Subject, Message):
        try:
            access_token = self.read_access_token()
        except:
            return("获取access_token失败！")
        else:
            url = 'https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token='
            data = {
                "touser": User,
                "msgtype": "text",
                "agentid": self.AGENTID,
                "text": {
                    "content": Subject + '\n' + Message
                    },
                "safe": "0"
                }
            values = bytes(json.dumps(data), 'utf-8')
            req = requests.post(url + access_token, values)
            response = json.loads(req.text)
            if response['errcode'] == 42001 or response['errcode'] == 40014:
                try:
                    access_token = self.get_access_token()
                except:
                    return("更新access_token失败！")
                else:
                    req = requests.post(url + access_token, values)
            return req.text

if __name__ == '__main__':
    User = sys.argv[1]
    Subject = str(sys.argv[2])
    Message = str(sys.argv[3])
    LOGFILE = '/tmp/Wechat_Message.log'
    wx = WeChat()
    send_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    log = wx.send_message(User, Subject, Message)
    try:
        with open(LOGFILE, 'a+') as f:
            f.write(' '.join([send_time, User, '->', Subject.replace('\n',' ')]) + '\n'\
                    + log + '\n\n')
    except:
        print(log)
