with open("programs/memory.hex", 'r') as file:
	lines = file.readlines()

data_mem = ""
instr_mem = ""
data_mem_done = False
data_address = False
instr_address = False

for line in lines:
	if line.startswith('@'):
		if data_mem_done:
			data_address = True
			instr_address = False
		else:
			instr_address = True
			data_mem_done = True
	else:
		if instr_address:
			data_mem += line.strip() + " "
		else:
			instr_mem += line.strip() + " "

with open('programs/data_mem.mem', 'w') as data_mem_file:
	data_mem_file.write(data_mem)

with open('programs/instr_mem.mem', 'w') as instr_mem_file:
	instr_mem_file.write(instr_mem)



