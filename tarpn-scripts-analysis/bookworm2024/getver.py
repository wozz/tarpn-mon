#!/usr/bin/env python3
# n9600a-cmd
# Python3
# Send commands to n9600a connected by serial port.
# Nino Carrillo
# 24 Feb 2023
# Exit codes
# 1 Wrong python version
# 2 Not enough command line arguments
# 3 Unable to open serial port
# 4 Invalid command
# 5 Invalid value
# 6 Timeout waiting for response

import serial
import sys
import time

def GracefulExit(port, code):
	try:
		port.close()
	except:
		pass
	finally:
		#print('Closed port ', port.port)
		sys.exit(code)

def AssembleKISSFrame(input_array):
	FESC = int(0xDB).to_bytes(1,'big')
	FEND = int(0xC0).to_bytes(1,'big')
	TFESC = int(0xDD).to_bytes(1,'big')
	TFEND = int(0xDC).to_bytes(1,'big')
	frame_index = 0
	result = bytearray()
	while(frame_index < len(input_array)):
		kiss_byte = input_array[frame_index]
		if kiss_byte.to_bytes(1,'big') == FESC:
			result.extend(FESC)
			result.extend(TFESC)
		elif kiss_byte.to_bytes(1, 'big') == FEND:
			result.extend(FESC)
			result.extend(TFEND)
		else:
			result.extend(kiss_byte.to_bytes(1, 'big'))
		frame_index += 1
	result = bytearray(FEND) +  result + bytearray(FEND)
	return result

if sys.version_info < (3, 0):
	print("Python version should be 3.x, exiting")
	sys.exit(1)


command_string = "GETVER"
command = bytearray()
value = bytearray()
command.extend(int(0x8).to_bytes(1,'big'))
value.extend(int(0).to_bytes(1,'big'))
get_response = 'yes'

try:
	port = serial.Serial(sys.argv[1], baudrate=57600, bytesize=8, parity='N', stopbits=1, xonxoff=0, rtscts=0, timeout=3)
except:
	print('Unable to open serial port.')
	sys.exit(3)

kiss_output_frame = AssembleKISSFrame(command + value)

frame_time = len(kiss_output_frame) * 10.0 / float(57600)
port.write(kiss_output_frame)

if get_response == 'yes':
	start_response_time = time.time()
	kiss_state = "non-escaped"
	kiss_frame = []
	FESC = 0xDB
	FEND = 0xC0
	TFESC = 0xDD
	TFEND = 0xDC
	frame_count = 0
	while frame_count < 1:
		elapsed_time = time.time() - start_response_time
		if (elapsed_time > 2):
			print('Maybe isn''t a NinoTNC?.')
			GracefulExit(port, 6)
		input_data = port.read(1)
		if input_data:
			if kiss_state == "non-escaped":
				if ord(input_data) == FESC:
					kiss_state = "escaped"
				elif ord(input_data) == FEND:
					if len(kiss_frame) > 0:
						frame_count += 1
						kiss_frame_string = ""
						for character in kiss_frame[1:]:
							kiss_frame_string += chr(character)
						print(kiss_frame_string)
						# kiss_frame = []
					else:
						kiss_frame = []
				else:
					kiss_frame.append(ord(input_data))
			elif kiss_state == "escaped":
				if ord(input_data) == TFESC:
					kiss_frame.append(FESC)
					kiss_state = "non-escaped"
				elif ord(input_data) == TFEND:
					kiss_frame.append(FEND)
					kiss_state = "non-escaped"


time.sleep(frame_time * 1.5)

GracefulExit(port, 0)
