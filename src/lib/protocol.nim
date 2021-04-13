import options
import sequtils
import strformat
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
    MemDataL = 0x500e
    MemDataS = 0x500f
    LatestDataL = 0x5021
    LatestDataS = 0x5022
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
proc get_int32(buf: string, idx: int): int32 =
  result = (buf[idx + 3].int32 shl 24) or
      (buf[idx + 2].int32 shl 16) or
      (buf[idx + 1].int32 shl 8) or
      buf[idx].int32

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
#
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


when isMainModule:
  import json

  let port = "ttyUSB3"
  let sensor = open_2jcie(port)
  let data_opt = sensor.get_latest_data_short()
  if data_opt.isSome:
    echo (%data_opt.get).pretty()
