import json
import options
import os
import sequtils
import strformat
import strutils
import times
import argparse
import lib/protocol

type
  Cmd {.pure.} = enum
    GetLatest = "get_latest"
    SetTime = "set_time"
    GetMemInfo = "get_meminfo"
    GetMemory = "get_memory"
    Unknown
  OutFmt {.pure.} = enum
    CSV = "CSV"
    JSON = "JSON"
  AppOptions = object
    port: string
    command: Cmd
    format: OutFmt
    args: string

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc parse_args(): AppOptions =
  var p = newParser("nim_2jcie"):
    argparse.option("-p", "--port", help = "USB serial port (ex. ttyUSB0)")
    argparse.option("-f", "--format", default = "JSON", help = "output format (JSON/CSV)")
    argparse.arg("command", help = "Select command [get_latest|get_meminfo|get_memory|set_time]")
    argparse.arg("arguments", default = "none")
  try:
    var opts = p.parse()
    if opts.help:
      quit(0)
    result.port = opts.port
    result.format = case opts.format.toUpper
      of "CSV": OutFmt.CSV
      else: OutFmt.JSON
    result.command = case opts.command.toLower
      of $Cmd.GetLatest: Cmd.GetLatest
      of $Cmd.SetTime: Cmd.SetTime
      of $Cmd.GetMemInfo: Cmd.GetMemInfo
      of $Cmd.GetMemory: Cmd.GetMemory
      else:
        echo p.help()
        quit(1)
    if result.command == Cmd.GetMemory and opts.arguments.len > 0 and
        opts.arguments != "none":
      result.args = opts.arguments
  except:
    echo p.help()
    quit(2)

#-------------------------------------------------------------------------------
# Command: Get Latest Data Short
#-------------------------------------------------------------------------------
proc cmd_get_latest(self: SensorDev): bool =
  let res = self.get_latest_data_short()
  if res.isSome:
    echo %res.get.data
    result = true

#-------------------------------------------------------------------------------
# Command: Get Memory Information
#-------------------------------------------------------------------------------
proc cmd_get_memory_info(self: SensorDev): bool =
  let res = self.get_memory_information()
  if res.isSome:
    echo &"Data in Memory: Last: {res.get.IdxLast} => Latest: {res.get.IdxLatest}"
    result = true

#-------------------------------------------------------------------------------
# Command: Get Memory Data
#-------------------------------------------------------------------------------
proc cmd_get_memory_data(self: SensorDev, idxStart, idxEnd: uint32,
    format: OutFmt): bool =
  var idx = 0
  var keys: seq[string]
  for data in self.get_memory_data_short(idxStart, idxEnd):
    var data_json = %(data.data)
    if format == OutFmt.CSV:
      if idx == 0:
        # echo header here
        for key in data_json.keys:
          keys.add(key)
        let header = "# timestamp, " & keys.join(", ")
        echo header
      var vals = newSeqOfCap[string](keys.len)
      vals.add(data.timecounter.format("yyyy-MM-dd'T'HH:mm:ss"))
      for key in keys:
        let val = data_json[key].getFloat
        vals.add(&"{val}")
      echo vals.join(", ")
    else:
      data_json["timestamp"] = newJInt(data.timecounter.toUnix)
      echo data_json
    idx.inc

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc parse_memory_index(self: SensorDev, arg: string): Option[(uint32, uint32)] =
  var range: (uint32, uint32)
  let memInfo_opt = self.get_memory_information()
  if memInfo_opt.isNone:
    return
  let memInfo = memInfo_opt.get
  if arg.contains("-"):
    # start-end
    let parts = arg.split("-").mapIt(it.strip)
    if parts.len != 2:
      return
    if parts[0] == "":
      range[0] = memInfo.IdxLast
    else:
      range[0] = parts[0].parseInt.uint32
    if parts[1] == "":
      range[1] = memInfo.IdxLatest
    else:
      range[1] = parts[1].parseInt.uint32
  elif arg.startsWith("o"):
    let nums = arg[1..^1].parseInt.uint32
    range[0] = memInfo.IdxLast
    range[1] = memInfo.IdxLast + nums - 1
    if range[1] > memInfo.IdxLatest:
      range[1] = memInfo.IdxLatest
  elif arg.startsWith("n"):
    let nums = arg[1..^1].parseInt.uint32
    range[1] = memInfo.IdxLatest
    range[0] = memInfo.IdxLatest - nums + 1
    if range[0] < memInfo.IdxLast:
      range[0] = memInfo.IdxLast
  else:
    return
  result = some(range)

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
proc main(): bool =
  let opts = parse_args()
  let sensor = open_2jcie(opts.port)
  case opts.command
    of Cmd.GetLatest:
      result = sensor.cmd_get_latest()
    of Cmd.SetTime:
      result = false
    of Cmd.GetMemInfo:
      result = sensor.cmd_get_memory_info()
    of Cmd.GetMemory:
      let range_opt = sensor.parse_memory_index(opts.args)
      if range_opt.isSome:
        let range = range_opt.get
        result = sensor.cmd_get_memory_data(range[0], range[1], opts.format)
    else: result = false


when isMainModule:
  let res = main()
  let exitcode = if res: 0 else: 1
  quit(exitcode)
