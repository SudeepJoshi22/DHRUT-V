import csv
import re

# Define the register mapping
register_mapping = {
    "zero": "x0",
    "ra": "x1",
    "sp": "x2",
    "gp": "x3",
    "tp": "x4",
    "t0": "x5",
    "t1": "x6",
    "t2": "x7",
    "s0": "x8",
    "s1": "x9",
    "a0": "x10",
    "a1": "x11",
    "a2": "x12",
    "a3": "x13",
    "a4": "x14",
    "a5": "x15",
    "a6": "x16",
    "a7": "x17",
    "s2": "x18",
    "s3": "x19",
    "s4": "x20",
    "s5": "x21",
    "s6": "x22",
    "s7": "x23",
    "s8": "x24",
    "s9": "x25",
    "s10": "x26",
    "s11": "x27",
    "t3": "x28",
    "t4": "x29",
    "t5": "x30",
    "t6": "x31"
}

# Open the CSV file
with open('spike.csv', newline='') as csvfile:
	# Create a CSV reader
	reader = csv.DictReader(csvfile)

	# Initialize list to store extracted register names
	register_names = []
	register_data = []
	gpr_col = []
    
	# Iterate over rows in the CSV file
	for row in reader:
		# Extract 'gpr' column and handle empty cells
		gpr_column = row.get('gpr', '')
		
		# Extract register names using regular expressions
		extracted_registers = re.findall(r'([a-z]\d):', gpr_column)

		# Extend the list of register names with extracted registers
		if extracted_registers:
			register_names.extend(extracted_registers)
		else:
			register_names.append('')  # Append an empty entry if no registers are found
		
		if gpr_column.strip() == '':
			register_data.append('')
		else:
			# Extract register names and data using regular expressions
			extracted_registers = re.findall(r'([a-z]\d):(\w+)', gpr_column)
			# Extend the list of register names and data with extracted values
			for reg, data in extracted_registers:
				register_data.append(data)


# Map register names to numeric register names
numeric_register_names = [register_mapping.get(reg, reg) if reg else '' for reg in register_names]

formatted_register_values = []
for name, data in zip(numeric_register_names, register_data):
    if name and data:  # If both name and data are non-empty
        formatted_register_values.append(f"{name}:{data}")
    else:  # If either name or data is empty
        formatted_register_values.append('') 
        
def overwrite_csv_gpr_column(csv_file, values):
	# Read the CSV file and store its data
	with open(csv_file, 'r', newline='') as csvfile:
		reader = csv.DictReader(csvfile)
		data = list(reader)

	# Update the 'gpr' column with the new values
	for row, value in zip(data, values):
		row['gpr'] = value

	# Write the updated data back to the CSV file
	with open(csv_file, 'w', newline='') as csvfile:
		fieldnames = data[0].keys()
		writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
		writer.writeheader()
		writer.writerows(data)
		

#print(numeric_register_names)
#print(register_data)
#print(formatted_register_values)

overwrite_csv_gpr_column('spike.csv', formatted_register_values)
print("Registers remapped from ABI names to Numeric Names")
