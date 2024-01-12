import sys
import os

audio_dir = sys.argv[1]
# the textgrid directory can be (optionally) supplied so that wavs without a textgrid are not diarized
if len(sys.argv) == 3:
    file_dir = sys.argv[2]
else:
    file_dir = audio_dir

from pyannote.audio import Pipeline
pipeline = Pipeline.from_pretrained(
    "pyannote/speaker-diarization-3.0",
    use_auth_token="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")

import torch
# pytorch only supports "cpu" or "cuda"
pipeline.to(torch.device("cpu"))

for filename in os.listdir(file_dir):
    if filename.endswith(".wav") or filename.endswith(".TextGrid"):
        basename = os.path.splitext(filename)[0]
        file = os.path.join(audio_dir, f"{basename}.wav")

        if not os.path.isfile(file):
            continue

        if not os.path.exists("diarized/"):
            os.makedirs("diarized/")

        out_path = f"diarized/{basename}"

        if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
            print(out_path + " already exists. Moving to next file...")
            continue
        else:

            out = open(out_path, "w")

            # apply pretrained pipeline
            diarization = pipeline(file, max_speakers=5)
    
            # print the result
            for turn, _, speaker in diarization.itertracks(yield_label=True):
                out.write(f"{turn.start:.1f} {turn.end:.1f} {speaker}\n")
    
            out.close()