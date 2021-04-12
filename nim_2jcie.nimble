# Package

version       = "0.1.0"
author        = "Takeyoshi Kikuchi"
description   = "Utility for OMRON 2JCIE-BU01"
license       = "MIT"
srcDir        = "src"
bin           = @["nim_2jcie"]


# Dependencies

requires "nim >= 1.4.4"
requires "serial >= 1.1.4"
