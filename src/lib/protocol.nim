import endians
import options
import sequtils
import strformat
import times
import serial
import crc

type
  SensorDev* = ref object
    port: string
    ser: SerialPort
  Cmd {.pure.} = enum
    Read = 0x01
    Write = 0x02
  Resp {.pure.} = enum
    Read = 0x01
    Write = 0x02
    ReadErr = 0x81
    WriteErr = 0x82
    Unknown = 0xff
  ErrCode {.pure.} = enum
    Crc = 0x01
    Cmd = 0x02
    Address = 0x03
    Length = 0x04
    Data = 0x05
    Busy = 0x06
  DataAddr* {.pure.} = enum
    MemIdxInfo = 0x5004
    MemDataL = 0x500e
    MemDataS = 0x500f
    LatestDataL = 0x5021
    LatestDataS = 0x5022
    LatestTimeCtr = 0x5201
    TimeSetting = 0x5202
  DataShort* = object
    temperature*: float
    humidity*: float
    light*: int16
    pressure*: float
    noise*: float
    eTVOC*: int16
    eCos*: int16
    discomfort*: float
    heat_stroke*: float
  # 0x5004
  MemoryInfo* = object
    IdxLatest*: uint32
    IdxLast*: uint32
  # 0x500f
  MemDataShort* = object
    memIdx*: uint32
    timecounter*: Time
    data*: DataShort
  # 0x5022
  LatestDataS* = object
    sequenceNo*: uint8
    data*: DataShort

const HEADER = "\x52\x42"

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc lb(val: uint16): char =
  result = (val and 0x00ff).char

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc hb(val: uint16): char =
  result = ((val and 0xff00) shr 8).char

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc get_int16(buf: string, idx: int): int16 =
  result = (buf[idx + 1].int16 shl 8) or buf[idx].int16

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc get_uint16(buf: string, idx: int): uint16 =
  result = (buf[idx + 1].uint16 shl 8) or buf[idx].uint16

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc get_int32(buf: string, idx: int): int32 =
  result = (buf[idx + 3].int32 shl 24) or
      (buf[idx + 2].int32 shl 16) or
      (buf[idx + 1].int32 shl 8) or
      buf[idx].int32

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc get_uint32(buf: string, idx: int): uint32 =
  result = (buf[idx + 3].uint32 shl 24) or
      (buf[idx + 2].uint32 shl 16) or
      (buf[idx + 1].uint32 shl 8) or
      buf[idx].uint32

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc toString(s: seq[char]): string =
  result = newStringOfCap(s.len)
  for ch in s:
    result.add(ch)

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc open_2jcie*(port: string): SensorDev =
  let device = &"/dev/{port}"
  let ser = newSerialPort(device)
  ser.open(115200, Parity.None, 8, StopBits.One)
  ser.setTimeouts(1000, 1000)
  result = new SensorDev
  result.port = device
  result.ser = ser

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc gen_frame(cmd: Cmd, address: DataAddr, data: string): string =
  let payloadlen: uint16 = (1 + 2 + data.len + 2).uint16
  var buf = newSeq[char](4 + payloadlen)
  buf[0..1] = HEADER # Header
  buf[2] = payloadlen.lb
  buf[3] = payloadlen.hb
  buf[4] = cmd.char
  buf[5] = address.uint16.lb
  buf[6] = address.uint16.hb
  buf[7..^3] = data
  let crc = calc_CRC16(buf[0..^3])
  buf[^2] = crc.lb
  buf[^1] = crc.hb
  result = buf.toString

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc recv(self: SensorDev): Option[string] =
  let header = self.ser.read(4)
  if header[0..1] != HEADER:
    return none(string)
  let restlen = get_int16(header, 2).int32
  let rest = self.ser.read(restlen)
  let received = header & rest
  if not (received[4].char in [Resp.Read.char, Resp.Write.char]):
    return none(string)
  let crc_calc = calc_CRC16(received[0..^3].toSeq)
  let crc_pkt = get_uint16(received, received.len - 2)
  if crc_calc == crc_pkt:
    result = some(received[7..^3])

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc send(self: SensorDev, frame: string): bool =
  let sendlen = self.ser.write(frame)
  result = if sendlen == frame.len: true else: false

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc send_recv(self: SensorDev, frame: string): Option[string] =
  if not self.send(frame):
    return none(string)
  result = self.recv()

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc decode_data_short(payload: string): DataShort =
  result.temperature = get_int16(payload, 0).float * 0.01
  result.humidity = get_int16(payload, 2).float * 0.01
  result.light = get_int16(payload, 4)
  result.pressure = get_int32(payload, 6).float * 0.001
  result.noise = get_int16(payload, 10).float * 0.01
  result.eTVOC = get_int16(payload, 12)
  result.eCos = get_int16(payload, 14)
  result.discomfort = get_int16(payload, 16).float * 0.01
  result.heat_stroke = get_int16(payload, 18).float * 0.01

#-------------------------------------------------------------------------------
# Cmd: Get Memory Information (0x5004)
#-------------------------------------------------------------------------------
proc get_memory_information*(self: SensorDev): Option[MemoryInfo] =
  let packet = gen_frame(Cmd.Read, DataAddr.MemIdxInfo, "")
  let res = self.send_recv(packet)
  if res.isNone:
    return none(MemoryInfo)
  let payload = res.get
  var memIdx: MemoryInfo
  memIdx.IdxLatest = get_uint32(payload, 0)
  memIdx.IdxLast = get_uint32(payload, 4)
  result = some(memIdx)

#-------------------------------------------------------------------------------
# Cmd: Get Memory Data Short (0x500f)
#-------------------------------------------------------------------------------
iterator get_memory_data_short*(self: SensorDev, idxStart, idxEnd: uint32): MemDataShort =
  block:
    let memIdx_opt = self.get_memory_information()
    if memIdx_opt.isNone:
      break
    let idxLast = memIdx_opt.get.IdxLast
    let idxLatest = memIdx_opt.get.IdxLatest
    if idxLast == 0 or idxLatest == 0:
      # recording not started
      break
    if idxStart < idxLast or idxEnd > idxLatest or idxStart >= idxEnd:
      break
    var cmd_payload = newString(8)
    var iStart = idxStart
    var iEnd = idxEnd
    littleEndian32(addr cmd_payload[0], addr iStart)
    littleEndian32(addr cmd_payload[4], addr iEnd)
    let packet = gen_frame(Cmd.Read, DataAddr.MemDataS, cmd_payload)
    if not self.send(packet):
      break
    let datacnt = (idxEnd - idxStart) + 1
    for i in 0..<datacnt:
      let res = self.recv()
      let payload = res.get
      var data: MemDataShort
      littleEndian32(addr data.memIdx, unsafeAddr payload[0])
      var tc: int64
      littleEndian64(addr tc, unsafeAddr payload[4])
      data.timecounter = fromUnix(tc)
      data.data = decode_data_short(payload[12..^1])
      yield data

#-------------------------------------------------------------------------------
# Cmd: Get Latest Data Short (0x5022)
#-------------------------------------------------------------------------------
proc get_latest_data_short*(self: SensorDev): Option[LatestDataS] =
  let packet = gen_frame(Cmd.Read, DataAddr.LatestDataS, "")
  let res = self.send_recv(packet)
  if res.isNone:
    return none(LatestDataS)
  let payload = res.get
  var data_s: LatestDataS
  data_s.sequenceNo = payload[0].uint8
  data_s.data = decode_data_short(payload[1..^1])
  result = some(data_s)

#-------------------------------------------------------------------------------
# Cmd: Get Time setting (0x5202)
#-------------------------------------------------------------------------------
proc get_time_setting*(self: SensorDev): Option[int64] =
  let packet = gen_frame(Cmd.Read, DataAddr.TimeSetting, "")
  let res = self.send_recv(packet)
  if res.isNone:
    return none(int64)
  let payload = res.get
  var timestamp: int64
  littleEndian64(addr timestamp, unsafeAddr payload[0])
  result = some(timestamp)

#-------------------------------------------------------------------------------
# Cmd: Set Time setting (0x5202)
#-------------------------------------------------------------------------------
proc set_time_setting*(self: SensorDev): Option[bool] =
  let timestamp_now = getTime().toUnix()
  var ts_now = newString(8)
  littleEndian64(addr ts_now[0], unsafeAddr timestamp_now)
  let packet = gen_frame(Cmd.Write, DataAddr.TimeSetting, ts_now)
  let res = self.send_recv(packet)
  if res.isNone:
    return none(bool)
  return some(true)


when isMainModule:
  import json

  let port = "ttyUSB0"
  let sensor = open_2jcie(port)
  # 0x5202: TimeSetting
  let ts_opt = sensor.get_time_setting()
  if ts_opt.isSome:
    let ts = ts_opt.get
    let datetime = ts.fromUnix.format("yyyy/MM/dd HH:mm:ss")
    echo &"Timestamp: {datetime}"
    # start logging
    #let ts_set_opt = sensor.set_time_setting()
    #if ts_set_opt.isSome:
    #  echo &"Timestamp set OK"
  # 0x5004
  let memInfo_opt = sensor.get_memory_information()
  if memInfo_opt.isSome:
    let memInfo = memInfo_opt.get
    echo &"MemoryIndex: Last: {memInfo.IdxLast}, Latest: {memInfo.IdxLatest}"
    var idx_start = memInfo.IdxLatest.int32 - 100 + 1
    if idx_start < 1:
      idx_start = 1
    for data in sensor.get_memory_data_short(idx_start.uint32, memInfo.IdxLatest):
      echo data
  let data_opt = sensor.get_latest_data_short()
  if data_opt.isSome:
    echo (%data_opt.get).pretty()
