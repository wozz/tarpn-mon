# N9600A Firmware Version reader
# Nino Carrillo 1 Sep 2020
# modified by Tadd KA2DEW 1 Sep 2020
# Exit codes:
# 0 version number reported
# 10 bad arguement count
# 11 unable to open specified serial port
# 12 bad version number read

import serial
import sys
import time

def EarlyExit(code):
    sys.exit(code)



def GracefulExit(port, code):
	try:
		port.close()
	except:
		pass
	finally:
		sys.exit(code)

if len(sys.argv) != 2:
	print("Wrong Argument count. Usage: python get_tnc_version <serial device>")
	EarlyExit(10)        ######################### EXIT 10

try:
	port = serial.Serial(sys.argv[1], baudrate=57600, bytesize=8, parity='N', stopbits=1, xonxoff=0, rtscts=0, timeout=0.2)
except:
	print("Unable to open serial port.")
	GracefulExit(port, 11) ######################### EXIT 11 
input_data = port.read(1)
while input_data != "":
	port.reset_input_buffer() # Discard all contents of input buffer
	input_data = port.read(1)
port.write("\xc0\xc0\x08\xc0") # Send KISS command to read firmware version
input_data = port.read(7) # Firmware version returns as 7 character KISS frame
low_printable = 31
high_printable = 128
version = input_data[2:6]
version_count = 0
for byte in version:
	try:
		if ord(byte[0]) < high_printable and ord(byte[0]) > low_printable:
			version_count = version_count + 1
	except:
		pass
	finally:
		pass
if version_count != 4:
	print("Invalid version received from TNC. Terminating.")
	print(version)
	GracefulExit(port, 12) ######################### EXIT 12
print(version)
GracefulExit(port, 0)

