import sys

def build_set (ctm_file, intervals):
    f=open(ctm_file, "r")
    lines=f.readlines()
    for line in lines:
        # to get scores that take the text of each interval into account,
        # set name, _, x, y, _ = line.split() to name, _, x, y, text = line.split()
        # and change intervals.add((name, x + i)) to intervals.add((name, x + i, text))
        name, _, x, y, _ = line.split()
        x=int(x.replace(".", ""))
        y=int(y.replace(".", ""))
        for i in range(y + 1):
            intervals.add((name, x + i))

def get_file_subset (interval_set, filename):
    return {element for element in interval_set if element[0] == filename}

def get_recall (reference, test):
    return len(reference & test) / len(reference)

def get_precision (reference, test):
    return len(test & reference) / len(test)

def get_f_beta_score (recall, precision):
    global beta
    return (1 + beta ** 2) / ((beta ** 2 / recall) + (1 / precision))

beta = float(sys.argv[1])
ctm_file_1 = sys.argv[2]
ctm_file_2 = sys.argv[3]
reference_intervals=set()
test_intervals=set()
file2ref_ints=dict()
file2test_ints=dict()


build_set(ctm_file_1, reference_intervals)
build_set(ctm_file_2, test_intervals)

test_file_list = {x[0] for x in test_intervals}

for file in test_file_list:
    file2ref_ints[file] = get_file_subset(reference_intervals, file)
    file2test_ints[file] = get_file_subset(test_intervals, file)

total_recall = get_recall(reference_intervals, test_intervals)
total_precision = get_precision(reference_intervals, test_intervals)

# # for outputting results into a text file
# print("Beta value: " + str(beta))
# print("Total recall: " + str(total_recall))
# print("Total precision: " + str(total_precision))
# print("Total F beta score: " + str(get_f_beta_score(total_recall, total_precision)))
# print()

# for file in sorted(test_file_list):
#     file_recall = get_recall(file2ref_ints[file], file2test_ints[file])
#     file_precision = get_precision(file2ref_ints[file], file2test_ints[file])
#     print("Recall for " + file + ": " + str(file_recall))
#     print("Precision for " + file + ": " + str(file_precision))
#     print("F beta score for " + file + ": " + str(get_f_beta_score(file_recall, file_precision)))
#     print()

# use when making excel charts
# use end="\t" for rows and end="\n" for columns
print(str(get_f_beta_score(total_recall, total_precision)), end="\t")
