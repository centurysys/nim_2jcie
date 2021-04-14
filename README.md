# OMRON 環境センサー 2JCIE-BU01 アプリ

OMRON 環境センサー 2JCIE-BU001 から計測データを取得したり、制御をしたりするアプリケーションです。

## How to Build

Nim で記述しているので、nimble でビルドします。

    $ nimble build -d:release -d:lto

## Usage

    root@plum:~# nim_2jcie -h
    nim_2jcie

    Usage:
      nim_2jcie [options] command [arguments]

    Arguments:
      command          Select command [get_latest|get_meminfo|get_memory|set_time]
      [arguments]      (default: none)

    Options:
      -p, --port=PORT            USB serial port (ex. ttyUSB0)
      -f, --format=FORMAT        output format (JSON/CSV) (default: JSON)
      -h, --help                 Show this help


### 最新計測データ取得

    root@plum:~# nim_2jcie -p ttyUSB0 get_latest
    {"temperature":25.47,"humidity":56.41,"light":865,"pressure":998.231,"noise":56.46,"eTVOC":15,"eCos":505,"discomfort":73.08,"heat_stroke":22.45}

### 保存件数取得

    root@plum:~# nim_2jcie -p ttyUSB0 get_meminfo
    Data in Memory: Last: 1 => Latest: 20583

#### 保存されているデータ取得

##### 最新 n 件

    user1@plum:~$ nim_2jcie -p ttyUSB0 --format=CSV get_memory n5
    # timestamp, temperature, humidity, light, pressure, noise, eTVOC, eCos, discomfort, heat_stroke
    2021-04-13T20:14:28, 25.35, 48.8, 46.0, 1007.877, 55.27, 0.0, 400.0, 72.10000000000001, 21.31
    2021-04-13T20:14:29, 25.36, 48.81, 46.0, 1007.881, 54.49, 0.0, 400.0, 72.11, 21.31
    2021-04-13T20:14:30, 25.36, 48.81, 46.0, 1007.883, 57.48, 0.0, 406.0, 72.11, 21.31
    2021-04-13T20:14:31, 25.37, 48.77, 46.0, 1007.883, 61.47, 0.0, 400.0, 72.12, 21.32
    2021-04-13T20:14:32, 25.37, 48.76, 46.0, 1007.885, 85.76000000000001, 0.0, 400.0, 72.12, 21.32

##### 最古 n 件

    user1@plum:~$ nim_2jcie -p ttyUSB0 --format=CSV get_memory o5
    # timestamp, temperature, humidity, light, pressure, noise, eTVOC, eCos, discomfort, heat_stroke
    2021-04-13T09:27:07, 26.45, 37.34, 710.0, 1016.578, 58.77, 36.0, 641.0, 72.16, 20.78
    2021-04-13T09:27:08, 26.46, 37.33, 710.0, 1016.57, 57.66, 36.0, 641.0, 72.17, 20.78
    2021-04-13T09:27:09, 26.48, 37.29, 710.0, 1016.567, 57.69, 35.0, 634.0, 72.19, 20.8
    2021-04-13T09:27:10, 26.46, 37.31, 710.0, 1016.569, 57.3, 36.0, 641.0, 72.17, 20.78
    2021-04-13T09:27:11, 26.48, 37.27, 712.0, 1016.572, 57.14, 38.0, 652.0, 72.18000000000001, 20.8

<br/>

### 応用

#### SORACOM Harvest Data に送信する

##### UDP
    root@plum:~# nim_2jcie -p ttyUSB0 get_latest|ncat -u harvest.soracom.io 8514

##### HTTP (curl 使用)

    root@plum:~# curl -v --data `nim_2jcie -p ttyUSB0 get_latest` harvest.soracom.io
    *   Trying 100.127.111.111:80...
    * TCP_NODELAY set
    * Connected to harvest.soracom.io (100.127.111.111) port 80 (#0)
    > POST / HTTP/1.1
    > Host: harvest.soracom.io
    > User-Agent: curl/7.68.0
    > Accept: */*
    > Content-Length: 154
    > Content-Type: application/x-www-form-urlencoded
    > 
    * upload completely sent off: 154 out of 154 bytes
    * Mark bundle as not supporting multiuse
    < HTTP/1.1 201 Created
    < Date: Wed, 14 Apr 2021 02:50:08 GMT
    < Content-Length: 0
    < Connection: close
    < 
    * Closing connection 0
    root@plum:~# 
