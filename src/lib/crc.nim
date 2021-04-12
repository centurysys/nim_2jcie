# =============================================================================
# CRC-CCITT(0xffff)/CRC16
# =============================================================================
proc createCrcTableLeft(poly: uint16): array[0..255, uint16] =
  for i in 0..255:
    var
      crc = 0'u16
      c: uint16 = uint16(i) shl 8
    for j in 0..7:
      if ((crc xor c) and 0x8000) > 0:
        crc = (crc shl 1) xor poly
      else:
        crc = crc shl 1
      c = c shl 1
    result[i] = crc

proc createCrcTableRight(poly: uint16): array[0..255, uint16] =
  for i in 0..255:
    var crc = i.uint16
    for j in 0..7:
      if (crc and 1'u16) != 0:
        crc = (crc shr 1) xor poly
      else:
        crc = crc shr 1
    result[i] = crc

const crcTable_CCITT = createCrcTableLeft(0x1021)
const crc16Table = createCrcTableRight(0xa001)

proc calc_CRC_CCITT*(buf: openArray[char|uint8]): uint16 =
  result = uint16(0xffff)
  for i in 0..buf.high:
    result = (result shl 8) xor crcTable_CCITT[((result shr 8) xor uint8(buf[i])) and 0x00ff]

proc calc_CRC16*(buf: openArray[char|uint8]): uint16 =
  result = uint16(0xffff)
  for i in 0..buf.high:
    result = (result shr 8) xor crc16Table[(result xor uint8(buf[i])) and 0x00ff]


when isMainModule:
  import strformat
  import sequtils

  let buf = "hoge".toSeq()
  var crc: uint16

  crc = calc_CRC_CCITT(buf)
  echo fmt"CRC-CCITT: {buf} -> 0x{crc:04x}"
  crc = calc_CRC16(buf)
  echo fmt"CRC-16: {buf} -> 0x{crc:04x}"
