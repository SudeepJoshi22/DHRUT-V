import csv


class Color:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    RESET = '\033[0m'

class MismatchError(Exception):
	pass

def extract_column(filename, column_name):
    """
    Extracts values from a specified column in a CSV file
    """
    with open(filename, 'r') as file:
        reader = csv.DictReader(file)
        column_values = [row[column_name].strip().replace(" ", "") for row in reader]
    return column_values

def compare_columns(file1, file2, column_to_compare):
	"""
	Compares the contents of specified columns in two CSV files
	"""
	column_values_1 = extract_column(file1, column_to_compare)
	column_values_2 = extract_column(file2, column_to_compare)

	# Ensure both lists have the same length
	max_length = max(len(column_values_1), len(column_values_2))
	column_values_1 += [''] * (max_length - len(column_values_1))
	column_values_2 += [''] * (max_length - len(column_values_2))

	# Load rows of file1
	with open(file1, 'r', newline='') as csvfile:
		reader = csv.reader(csvfile)
		rows_file1 = list(reader)

	# Iterate over both columns simultaneously

	for i, (val1, val2, row_file1) in enumerate(zip(column_values_1, column_values_2, rows_file1)):
		if val1!=val2:
			log_file = open('compare.log','a')
			#print(f"Mismatch at Instruction {i+1}: '{val1}'(spike) != '{val2}'(RTL)")
			log_file.write(f"Mismatch at Instruction {i+1}: '{val1}'(spike) != '{val2}'(RTL)\n")
			#print(f"{rows_file1[i+1]}(spike)")
			log_file.write(f"{rows_file1[i+1]}(spike)\n")
			log_file.close()
	'''
	# Iterate over both columns simultaneously
	for i, (val1, val2) in enumerate(zip(column_values_1, column_values_2)):
	if val1 != val2:
	print(f"Mismatch at Instruction {i+1}: '{val1}' != '{val2}'")
	'''
	if column_values_1 != column_values_2:
		raise MismatchError(f"Contents of column '{column_to_compare}' are different between the two files")

if __name__ == "__main__":

	pass_count = 0
	
	#Compare PC Column
	file1 = "spike.csv"  
	file2 = "IF_log.csv"  
	column_to_compare = "pc" 
	
	try:
		compare_columns(file1, file2, column_to_compare)
		print(Color.GREEN + f"{column_to_compare} in both RTL and Spike are Matching" + Color.RESET)
		pass_count += 1
	except MismatchError as e:
		print(Color.RED + f"{column_to_compare} in both RTL and Spike are not Matching" + Color.RESET)
	
	#Compare binary Column
	file1 = "spike.csv"  
	file2 = "IF_log.csv"  
	column_to_compare = "binary" 
	
	try:
		compare_columns(file1, file2, column_to_compare)
		print(Color.GREEN + f"{column_to_compare} in both RTL and Spike are Matching" + Color.RESET)
		pass_count += 1
	except MismatchError as e:
		print(Color.RED + f"{column_to_compare} in both RTL and Spike are not Matching" + Color.RESET)

	#Compare gpr Column
	file1 = "spike.csv"  
	file2 = "ID_log.csv"  
	column_to_compare = "gpr" 
	
	try:
		compare_columns(file1, file2, column_to_compare)
		print(Color.GREEN + f"{column_to_compare} in both RTL and Spike are Matching" + Color.RESET)
		pass_count += 1
	except MismatchError as e:
		print(Color.RED + f"{column_to_compare} in both RTL and Spike are not Matching" + Color.RESET)

	#Compare csr Column
	file1 = "spike.csv"  
	file2 = "MEM_log.csv"  
	column_to_compare = "csr" 
	
	try:
		compare_columns(file1, file2, column_to_compare)
		print(Color.GREEN + f"{column_to_compare} in both RTL and Spike are Matching" + Color.RESET)
		pass_count += 1
	except MismatchError as e:
		print(Color.RED + f"{column_to_compare} in both RTL and Spike are not Matching" + Color.RESET)

	if pass_count == 4:
		print( Color.GREEN + "/////////////////////////////\n" + "!!! SIMULATION PASSED :) !!!\n" + "/////////////////////////////" + Color.RESET)
	else:
		print(Color.RED + "/////////////////////////////\n" + "!!! SIMULATION FAILED :( !!!\n" + "/////////////////////////////" + Color.RESET)
