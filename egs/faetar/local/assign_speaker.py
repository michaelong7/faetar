import sys
from decimal import Decimal

# sets must have elements in tuple form (interval start, interval end, interval name)
def get_intersection (set1, set2):
    intersection_set = set()
    for element_a in set1:
        (element_a_start, element_a_end, element_a_name) = element_a

        for element_b in set2:
            (element_b_start, element_b_end, element_b_name) = element_b

            if element_a_start <= element_b_end and element_a_end >= element_b_start:
                overlap_start = max(element_a_start, element_b_start)
                overlap_end = min(element_a_end, element_b_end)
                intersection_set.add((overlap_start, overlap_end, element_a_name, element_b_name))

    return intersection_set

def filter_coverage (text_set, merged_set, threshold):
    coverage_filtered_set = set()

    for text_element in text_set:
        (utterance_start, utterance_end, utterance) = text_element
        utterance_length = utterance_end - utterance_start
        total_coverage_set = {element for element in merged_set if element[3] == utterance and element[0] >= utterance_start and element[1] <= utterance_end}

        # defining coverage_start / end in this way works since get_intersection forces merged_set boundaries 
        # to start and end at utterance boundaries
        coverage_start = min(total_coverage_set, key = lambda a: a[0], default = (0, 0))
        coverage_end = max(total_coverage_set, key = lambda a: a[1], default = (0, 0))
        coverage_length = coverage_end[1] - coverage_start[0]

        if (coverage_length / utterance_length) >= threshold:
            coverage_filtered_set.update(total_coverage_set)
        else:
            coverage_filtered_set.add((utterance_start, utterance_end, "no_speaker", utterance))
    
    return coverage_filtered_set

# this assumes that filter_coverage has been applied so that 
# all of the utterances are contained in the merged set
def filter_ambiguity_and_absolute (text_set, covered_set, ambiguity_threshold, absolute_threshold):
    ambiguity_filtered_set = set()

    for text_element in text_set:
        (utterance_start, utterance_end, utterance) = text_element
        relevant_speaker_set = {element for element in covered_set if element[3] == utterance and element[0] >= utterance_start and element[1] <= utterance_end}
        speaker_name_set = {element[2] for element in relevant_speaker_set}
        speaker_coverage_set = {(speaker, sum(element[1] - element[0] for element in relevant_speaker_set if element[2] == speaker)) for speaker in speaker_name_set}

        main_speaker = max(speaker_coverage_set, key = lambda a: a[1])
        other_speaker_set = speaker_coverage_set - {main_speaker}

        if check_absolute(other_speaker_set, absolute_threshold):
            ambiguity_filtered_set.add((utterance_start, utterance_end, "multiple_utterances", utterance))
            continue

        other_speaker_coverage = sum({element[1] for element in other_speaker_set})

        # other_speaker_coverage == 0 prevents division by 0 errors
        if other_speaker_coverage == 0 or (main_speaker[1] / other_speaker_coverage) >= ambiguity_threshold:
            ambiguity_filtered_set.add((utterance_start, utterance_end, main_speaker[0], utterance))
        else:
            ambiguity_filtered_set.add((utterance_start, utterance_end, "ambiguous_speaker", utterance))

    return ambiguity_filtered_set


def check_absolute (speaker_set, threshold):
    for speaker in speaker_set:
        if speaker[1] > (threshold * 100):
            return True 
    return False


def build_set (file, interval_set):
    f = open(file, "r")
    lines = f.readlines()
    for line in lines:
        start, end, interval_name = line.split(maxsplit = 2)
        # using Decimal avoids float rounding problems in the output
        interval_set.add((int(Decimal(start) * 100), int(Decimal(end) * 100), interval_name.strip()))
    f.close()

diarized_file = sys.argv[1]
diarized_file_text = sys.argv[2]
coverage_threshold = float(sys.argv[3])
ambiguity_threshold = float(sys.argv[4])
absolute_threshold = float(sys.argv[5])
speaker_intervals = set()
text_intervals = set()
merged_intervals = set()

build_set(diarized_file, speaker_intervals)
build_set(diarized_file_text, text_intervals)

# the filtering functions assume that the first argument of get_intersection is the set of speaker intervals
merged_intervals = get_intersection(speaker_intervals, text_intervals)

covered = set()
disambiguated = set()
covered = filter_coverage(text_intervals, merged_intervals, coverage_threshold)
disambiguated = filter_ambiguity_and_absolute(text_intervals, covered, ambiguity_threshold, absolute_threshold)

# for element in sorted(speaker_intervals):
#     print(element)

# print()

# for element in sorted(text_intervals, key = lambda a: a[1]):
#     print(element)

# print()

# for element in sorted(merged_intervals):
#     print((Decimal(element[0]) / 100), (Decimal(element[1]) / 100), element[2], element[3])

# print()

for element in sorted(disambiguated):
    print((Decimal(element[0]) / 100), (Decimal(element[1]) / 100), element[2], element[3], sep = '\t')
